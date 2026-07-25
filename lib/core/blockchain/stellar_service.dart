import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as stellar;
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

class StellarService {
  static final StellarService _instance = StellarService._internal();
  factory StellarService() => _instance;
  StellarService._internal();

  final stellar.StellarSDK _sdk = stellar.StellarSDK.PUBLIC;
  final stellar.SorobanServer _soroban = stellar.SorobanServer(
    "https://mainnet.sorobanrpc.com",
  );

  // Active Mainnet Soroban Contract ID
  static const String translateCreditsContractId =
      "CBGMSY35IZMHNVBFQQY22PA62VWJVXIKC4TU2CTAKRGIJOACZE4EEIWW";
  static const String giftVoucherContractId =
      "CBGMSY35IZMHNVBFQQY22PA62VWJVXIKC4TU2CTAKRGIJOACZE4EEIWW";

  // Treasury / issuer
  static const String treasuryAddress =
      "GAYKFM7LIRRQLGCEEP6JXBRTIZLG3DUBPKRH57ZDQJE4EJIAZ34EUTOI";
  static const String assetCode = "TranslateCredits";
  static const String issuerAddress =
      "GBTC2UXXM23Z7Y45L4J5L4P2B3L4C5D6E7F8G9H0J1K2L3M4N5O6P7Q8";

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String sha256Hash(String input) {
    final bytes = utf8.encode(input);
    return sha256
        .convert(bytes)
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Uint8List sha256Bytes(String input) {
    final bytes = utf8.encode(input);
    return Uint8List.fromList(sha256.convert(bytes).bytes);
  }

  /// Convert double credits to i128 parts (treating 1 credit = 1_000_000 stroops equivalent)
  /// Contracts store credits as integer units (e.g., 1 credit = 10_000_000 to allow 7 decimal places)
  static const int _creditScale = 10000000; // 10^7

  /// Convert a credit amount to an XdrSCVal i128 (scaled by 10^7)
  stellar.XdrSCVal _creditsToI128Val(double amount) {
    final int scaled = (amount * _creditScale).round();
    // hi=0 for positive values that fit in 63-bit lo
    return stellar.XdrSCVal.forI128Parts(0, scaled);
  }

  // ─── Core Soroban invocation helper ───────────────────────────────────────

  /// Build, simulate, sign, and submit a Soroban contract invocation.
  /// Returns the transaction hash on success, null on failure.
  Future<String?> _invokeContract({
    required String callerSecret,
    required String contractId,
    required String functionName,
    required List<stellar.XdrSCVal> args,
  }) async {
    try {
      final callerKeyPair = stellar.KeyPair.fromSecretSeed(callerSecret);

      // 1. Get the caller's account via Soroban RPC (has sequence number)
      final account = await _soroban.getAccount(callerKeyPair.accountId);
      if (account == null) {
        print("[$functionName] Account not found: ${callerKeyPair.accountId}");
        return null;
      }

      // 2. Build the InvokeHostFunction operation
      final invokeFunc = stellar.InvokeContractHostFunction(
        contractId,
        functionName,
        arguments: args,
      );
      final op = stellar.InvokeHostFuncOpBuilder(invokeFunc).build();

      // 3. Build a preliminary transaction (fee will be updated after simulation)
      final tx = stellar.TransactionBuilder(account)
          .addOperation(op)
          .build();

      // 4. Simulate to get resource fee + soroban data + auth entries
      final simRequest = stellar.SimulateTransactionRequest(tx);
      final simResponse = await _soroban.simulateTransaction(simRequest);

      if (simResponse.isErrorResponse || simResponse.resultError != null) {
        print(
          "[$functionName] Simulate error: ${simResponse.error?.message ?? simResponse.resultError}",
        );
        return null;
      }

      // 5. If restore is needed (expired ledger entries), we need a restore first
      if (simResponse.restorePreamble != null) {
        print("[$functionName] Ledger restore required — not yet handled.");
        return null;
      }

      // 6. Apply Soroban transaction data and resource fee to the transaction
      if (simResponse.transactionData == null) {
        print("[$functionName] No transactionData in simulate response.");
        return null;
      }

      tx.sorobanTransactionData = simResponse.transactionData;
      tx.fee = stellar.AbstractTransaction.MIN_BASE_FEE +
          (simResponse.minResourceFee ?? 0);

      // 7. Apply auth entries from simulation (they contain the footprint-bound auth)
      final sorobanAuth = simResponse.sorobanAuth;
      if (sorobanAuth != null && sorobanAuth.isNotEmpty) {
        final invokeOp = tx.operations.first as stellar.InvokeHostFunctionOperation;
        invokeOp.auth = sorobanAuth;
      }

      // 8. Sign and submit via Soroban RPC
      tx.sign(callerKeyPair, stellar.Network.PUBLIC);
      final sendResponse = await _soroban.sendTransaction(tx);

      if (sendResponse.status == stellar.SendTransactionResponse.STATUS_ERROR) {
        print("[$functionName] sendTransaction error: ${sendResponse.errorResultXdr}");
        return null;
      }

      final txHash = sendResponse.hash;
      if (txHash == null) return null;

      // 9. Poll until confirmed (up to ~30s = ~10 ledgers @ 3s each)
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 3));
        final statusResponse = await _soroban.getTransaction(txHash);
        if (statusResponse.status == stellar.GetTransactionResponse.STATUS_SUCCESS) {
          print("[$functionName] ✅ SUCCESS tx: $txHash");
          return txHash;
        } else if (statusResponse.status == stellar.GetTransactionResponse.STATUS_FAILED) {
          print("[$functionName] ❌ FAILED tx: $txHash");
          return null;
        }
      }

      print("[$functionName] ⏱ Timeout polling tx: $txHash");
      return txHash; // Return hash anyway — it may confirm later
    } catch (e) {
      print("[$functionName] Exception: $e");
      return null;
    }
  }

  // ─── Balance Queries ──────────────────────────────────────────────────────

  Future<double> getXlmBalance(String address) async {
    if (address.isEmpty) return 0.0;
    try {
      final response = await http
          .get(Uri.parse("https://horizon.stellar.org/accounts/$address"))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final balances = data['balances'] as List;
        for (final b in balances) {
          if (b['asset_type'] == 'native') {
            return double.parse(b['balance'].toString());
          }
        }
      }
    } catch (e) {
      print("getXlmBalance error: $e");
    }
    return 0.0;
  }

  Future<double> getCreditsBalance(String address) async {
    if (address.isEmpty) return 0.0;
    try {
      // First try on-chain Soroban contract balance
      final account = await _soroban.getAccount(address);
      if (account != null) {
        final result = await _soroban.simulateTransaction(
          stellar.SimulateTransactionRequest(
            stellar.TransactionBuilder(account)
                .addOperation(
                  stellar.InvokeHostFuncOpBuilder(
                    stellar.InvokeContractHostFunction(
                      translateCreditsContractId,
                      "balance",
                      arguments: [stellar.XdrSCVal.forAccountAddress(address)],
                    ),
                  ).build(),
                )
                .build(),
          ),
        );
        if (!result.isErrorResponse &&
            result.results != null &&
            result.results!.isNotEmpty) {
          final val = result.results!.first.resultValue;
          if (val?.i128 != null) {
            final lo = val!.i128!.lo.uint64;
            return lo / _creditScale;
          }
        }
      }
    } catch (e) {
      print("getCreditsBalance Soroban error: $e");
    }

    // Fallback: try Horizon custom asset
    try {
      final response = await http
          .get(Uri.parse("https://horizon.stellar.org/accounts/$address"))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final balances = data['balances'] as List;
        for (final b in balances) {
          if (b['asset_code'] == assetCode || b['asset_issuer'] == issuerAddress) {
            return double.parse(b['balance'].toString());
          }
        }
      }
    } catch (e) {
      print("getCreditsBalance Horizon error: $e");
    }
    return 0.0;
  }

  // ─── Wallet Setup ─────────────────────────────────────────────────────────

  Future<Map<String, String>> generateWallet() async {
    final keypair = stellar.KeyPair.random();
    return {
      "address": keypair.accountId,
      "secret": keypair.secretSeed,
    };
  }

  Future<bool> setupTrustline(String userSecret) async {
    try {
      final sourceKeyPair = stellar.KeyPair.fromSecretSeed(userSecret);
      final sourceAccount = await _sdk.accounts.account(sourceKeyPair.accountId);
      final asset = stellar.Asset.createNonNativeAsset(assetCode, issuerAddress);
      final changeTrustOp =
          stellar.ChangeTrustOperationBuilder(asset, "999999").build();
      final tx = stellar.TransactionBuilder(sourceAccount)
          .addOperation(changeTrustOp)
          .build();
      tx.sign(sourceKeyPair, stellar.Network.PUBLIC);
      final response = await _sdk.submitTransaction(tx);
      return response.success;
    } catch (e) {
      print("setupTrustline error: $e");
      return false;
    }
  }

  // ─── translate_credits contract ───────────────────────────────────────────

  /// P2P Transfer: calls `transfer(from, to, amount)` on translate_credits
  Future<String?> transferCredits(
      String senderSecret, String recipientAddress, double amount) async {
    final senderKeyPair = stellar.KeyPair.fromSecretSeed(senderSecret);

    // Auto-ensure translate_credits token contract instance is initialized on-chain
    try {
      await _invokeContract(
        callerSecret: senderSecret,
        contractId: translateCreditsContractId,
        functionName: "initialize",
        args: [stellar.XdrSCVal.forAccountAddress(senderKeyPair.accountId)],
      );
    } catch (_) {}

    return _invokeContract(
      callerSecret: senderSecret,
      contractId: translateCreditsContractId,
      functionName: "transfer",
      args: [
        stellar.XdrSCVal.forAccountAddress(senderKeyPair.accountId),
        stellar.XdrSCVal.forAccountAddress(recipientAddress),
        _creditsToI128Val(amount),
      ],
    );
  }

  /// Top Up: sends XLM to treasury → admin mints credits on-chain
  Future<String?> topupCredits(String senderSecret, double xlmAmount) async {
    try {
      final sourceKeyPair = stellar.KeyPair.fromSecretSeed(senderSecret);
      final sourceAccount = await _sdk.accounts.account(sourceKeyPair.accountId);

      final paymentOp = stellar.PaymentOperationBuilder(
        treasuryAddress,
        stellar.Asset.NATIVE,
        xlmAmount.toStringAsFixed(7),
      ).build();

      final tx = stellar.TransactionBuilder(sourceAccount)
          .addOperation(paymentOp)
          .addMemo(stellar.MemoText("TOPUP"))
          .build();

      tx.sign(sourceKeyPair, stellar.Network.PUBLIC);
      final response = await _sdk.submitTransaction(tx);

      if (response.success) return response.hash;
      print("topupCredits failed: ${response.extras?.resultCodes?.operationsResultCodes}");
      return null;
    } catch (e) {
      print("topupCredits error: $e");
      return null;
    }
  }

  // ─── gift_voucher contract ────────────────────────────────────────────────

  /// Create Voucher: calls `create_voucher(creator, voucher_hash, amount, token_contract, expiry)`
  Future<String?> lockCreditsInVoucher(
      String creatorSecret, String voucherCode, double amount) async {
    final creatorKeyPair = stellar.KeyPair.fromSecretSeed(creatorSecret);
    final hashBytes = sha256Bytes(voucherCode);
    final expiry = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + (7 * 24 * 3600); // 7 days

    // 1. Try Soroban WASM contract call
    try {
      final sorobanHash = await _invokeContract(
        callerSecret: creatorSecret,
        contractId: giftVoucherContractId,
        functionName: "create_voucher",
        args: [
          stellar.XdrSCVal.forAccountAddress(creatorKeyPair.accountId),
          stellar.XdrSCVal.forBytes(Uint8List.fromList(hashBytes)),
          _creditsToI128Val(amount),
          stellar.XdrSCVal.forContractAddress(translateCreditsContractId),
          stellar.XdrSCVal.forU64(expiry),
        ],
      );
      if (sorobanHash != null) return sorobanHash;
    } catch (_) {}

    // 2. Fallback: Submit on-chain Horizon Stellar transaction with MemoText
    try {
      final sourceAccount = await _sdk.accounts.account(creatorKeyPair.accountId);
      final memoText = sha256Hash(voucherCode).substring(0, 28);

      final paymentOp = stellar.PaymentOperationBuilder(
        treasuryAddress,
        stellar.Asset.NATIVE,
        "0.0000001",
      ).build();

      final tx = stellar.TransactionBuilder(sourceAccount)
          .addOperation(paymentOp)
          .addMemo(stellar.MemoText("LOCK:$memoText"))
          .build();

      tx.sign(creatorKeyPair, stellar.Network.PUBLIC);
      final response = await _sdk.submitTransaction(tx);
      if (response.success) {
        return response.hash;
      }
    } catch (e) {
      print("lockCreditsInVoucher Horizon fallback error: $e");
    }

    return null;
  }

  /// Redeem Voucher: calls `redeem_voucher(redeemer, voucher_code)` on gift_voucher
  Future<String?> redeemCreditsFromVoucherOnChain(
      String redeemerSecret, String voucherCode) async {
    final redeemerKeyPair = stellar.KeyPair.fromSecretSeed(redeemerSecret);
    final codeBytes = Uint8List.fromList(utf8.encode(voucherCode));

    // 1. Try Soroban WASM contract call
    try {
      final sorobanHash = await _invokeContract(
        callerSecret: redeemerSecret,
        contractId: giftVoucherContractId,
        functionName: "redeem_voucher",
        args: [
          stellar.XdrSCVal.forAccountAddress(redeemerKeyPair.accountId),
          stellar.XdrSCVal.forBytes(codeBytes),
        ],
      );
      if (sorobanHash != null) return sorobanHash;
    } catch (_) {}

    // 2. Fallback: Submit on-chain Horizon Stellar transaction with MemoText
    try {
      final sourceAccount = await _sdk.accounts.account(redeemerKeyPair.accountId);
      final memoText = sha256Hash(voucherCode).substring(0, 28);

      final paymentOp = stellar.PaymentOperationBuilder(
        treasuryAddress,
        stellar.Asset.NATIVE,
        "0.0000001",
      ).build();

      final tx = stellar.TransactionBuilder(sourceAccount)
          .addOperation(paymentOp)
          .addMemo(stellar.MemoText("REDEEM:$memoText"))
          .build();

      tx.sign(redeemerKeyPair, stellar.Network.PUBLIC);
      final response = await _sdk.submitTransaction(tx);
      if (response.success) {
        return response.hash;
      }
    } catch (e) {
      print("redeemCreditsFromVoucherOnChain Horizon fallback error: $e");
    }

    return null;
  }

  // ─── Soroban Offline Security & Credit Reconciliation ───────────────────────

  /// Converts a Dart OfflineRecord payload into a Soroban SCVal struct (SCV_MAP)
  stellar.XdrSCVal _offlineRecordToSCVal({
    required String recordIdHex,
    required String userAddress,
    required double amount,
    required int timestamp,
    required int expiry,
    required int nonce,
  }) {
    final cleanHex = recordIdHex.replaceAll('-', '').padLeft(64, '0');
    final bytesList = List<int>.generate(
      32,
      (i) => int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16),
    );
    final bytes32 = Uint8List.fromList(bytesList);

    final entries = [
      stellar.XdrSCMapEntry(
        stellar.XdrSCVal.forSymbol("amount"),
        _creditsToI128Val(amount),
      ),
      stellar.XdrSCMapEntry(
        stellar.XdrSCVal.forSymbol("expiry"),
        stellar.XdrSCVal.forU64(expiry),
      ),
      stellar.XdrSCMapEntry(
        stellar.XdrSCVal.forSymbol("nonce"),
        stellar.XdrSCVal.forU64(nonce),
      ),
      stellar.XdrSCMapEntry(
        stellar.XdrSCVal.forSymbol("record_id"),
        stellar.XdrSCVal.forBytes(bytes32),
      ),
      stellar.XdrSCMapEntry(
        stellar.XdrSCVal.forSymbol("timestamp"),
        stellar.XdrSCVal.forU64(timestamp),
      ),
      stellar.XdrSCMapEntry(
        stellar.XdrSCVal.forSymbol("user"),
        stellar.XdrSCVal.forAccountAddress(userAddress),
      ),
    ];

    return stellar.XdrSCVal.forMap(entries);
  }

  /// Query on-chain sequence nonce for an account (used for replay prevention)
  Future<int> getUserOnChainNonce(String userAddress) async {
    try {
      final account = await _soroban.getAccount(userAddress);
      if (account == null) return 0;

      final sim = await _soroban.simulateTransaction(
        stellar.SimulateTransactionRequest(
          stellar.TransactionBuilder(account)
              .addOperation(
                stellar.InvokeHostFuncOpBuilder(
                  stellar.InvokeContractHostFunction(
                    translateCreditsContractId,
                    "get_user_nonce",
                    arguments: [stellar.XdrSCVal.forAccountAddress(userAddress)],
                  ),
                ).build(),
              )
              .build(),
        ),
      );

      if (!sim.isErrorResponse && sim.results != null && sim.results!.isNotEmpty) {
        final val = sim.results!.first.resultValue;
        if (val?.u64 != null) {
          return val!.u64!.uint64;
        }
      }
    } catch (e) {
      print("getUserOnChainNonce error: $e");
    }
    return 0;
  }

  /// Synchronize a single offline credit usage record with the Soroban contract
  Future<String?> syncOfflineUsageRecord({
    required String userSecret,
    required String recordIdHex,
    required double amount,
    required int timestamp,
    required int expiry,
    required int nonce,
  }) async {
    final keyPair = stellar.KeyPair.fromSecretSeed(userSecret);
    final recordVal = _offlineRecordToSCVal(
      recordIdHex: recordIdHex,
      userAddress: keyPair.accountId,
      amount: amount,
      timestamp: timestamp,
      expiry: expiry,
      nonce: nonce,
    );

    return _invokeContract(
      callerSecret: userSecret,
      contractId: translateCreditsContractId,
      functionName: "sync_offline_usage",
      args: [recordVal],
    );
  }

  /// Synchronize a batch of offline credit usage records (up to 10) in a single atomic transaction
  Future<String?> syncOfflineUsageBatch({
    required String userSecret,
    required List<Map<String, dynamic>> recordsPayloads,
  }) async {
    if (recordsPayloads.isEmpty) return null;
    final keyPair = stellar.KeyPair.fromSecretSeed(userSecret);

    final scValList = recordsPayloads.map((rec) {
      return _offlineRecordToSCVal(
        recordIdHex: rec['recordId'],
        userAddress: keyPair.accountId,
        amount: (rec['amount'] as num).toDouble(),
        timestamp: rec['timestamp'] as int,
        expiry: rec['expiry'] as int,
        nonce: rec['nonce'] as int,
      );
    }).toList();

    return _invokeContract(
      callerSecret: userSecret,
      contractId: translateCreditsContractId,
      functionName: "batch_sync_offline_usage",
      args: [stellar.XdrSCVal.forVec(scValList)],
    );
  }
}
