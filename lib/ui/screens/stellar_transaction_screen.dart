import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as stellar;

import '../../core/database/database_helper.dart';
import '../../core/models/models.dart';

class StellarTransactionScreen extends StatefulWidget {
  const StellarTransactionScreen({super.key});

  @override
  State<StellarTransactionScreen> createState() => _StellarTransactionScreenState();
}

class _StellarTransactionScreenState extends State<StellarTransactionScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _amountController = TextEditingController();
  final _secretKeyController = TextEditingController();

  // Stellar Network Config
  final stellar.StellarSDK _sdk = stellar.StellarSDK.TESTNET;
  static const String issuerAddress = "GBTC2UXXM23Z7Y45L4J5L4P2B3L4C5D6E7F8G9H0J1K2L3M4N5O6P7Q8";
  static const String customAssetCode = "TranslateCredits";

  // Network State
  bool _isOnline = true;

  // Wallet State
  String? _localSecretKey;
  String? _localAccountId;
  double _xlmBalance = 0.0;
  double _creditsBalance = 0.0;
  bool _hasTrustline = false;

  List<StellarTransaction> _transactions = [];
  bool _isLoading = false;
  String _statusMessage = "";
  String _activeTab = "XLM"; // "XLM" or "TranslateCredits"

  @override
  void initState() {
    super.initState();
    _loadOrCreateWallet();
    _loadTransactions();
  }

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  // Load or generate local wallet
  void _loadOrCreateWallet() {
    final keypair = stellar.KeyPair.random();
    _localSecretKey = keypair.secretSeed;
    _localAccountId = keypair.accountId;
    _secretKeyController.text = _localSecretKey!;
    _fetchBalances();
  }

  void _importSecretKey(String secretKey) {
    try {
      final keypair = stellar.KeyPair.fromSecretSeed(secretKey.trim());
      setState(() {
        _localSecretKey = secretKey.trim();
        _localAccountId = keypair.accountId;
      });
      _fetchBalances();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Stellar wallet imported successfully!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid Stellar Secret Key format.")),
      );
    }
  }

  Future<void> _fetchBalances() async {
    if (_localAccountId == null) return;

    if (!_isOnline) {
      return; // Keep cached/fallback balance when offline
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final account = await _sdk.accounts.account(_localAccountId!);
      double newXlm = 0.0;
      double newCredits = 0.0;
      bool foundTrustline = false;

      for (var balance in account.balances) {
        if (balance.assetType == 'native') {
          newXlm = double.parse(balance.balance);
        } else if (balance.assetCode == customAssetCode && balance.assetIssuer == issuerAddress) {
          newCredits = double.parse(balance.balance);
          foundTrustline = true;
        }
      }

      if (mounted) {
        setState(() {
          _xlmBalance = newXlm;
          _creditsBalance = newCredits;
          _hasTrustline = foundTrustline;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Account might not exist on ledger yet (needs Friendbot funding)
      if (mounted) {
        setState(() {
          _xlmBalance = 0.0;
          _creditsBalance = 0.0;
          _hasTrustline = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTransactions() async {
    final list = await _dbHelper.getStellarTransactions();
    setState(() {
      _transactions = list;
    });
  }

  // Stellar Friendbot to fund account with 10k XLM
  Future<void> _fundWithFriendbot() async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Friendbot is unavailable offline.")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Funding account via Friendbot...";
    });

    try {
      final response = await http.get(Uri.parse("https://friendbot.stellar.org?addr=$_localAccountId"));
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Friendbot Success! +10,000 XLM credited!")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Friendbot response: ${response.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Friendbot request failed: ${e.toString()}")),
      );
    } finally {
      _fetchBalances();
    }
  }

  // Setup trustline for TranslateCredits
  Future<void> _establishTrustline() async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot establish trustline offline.")),
      );
      return;
    }

    if (_localSecretKey == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Establishing trustline for TranslateCredits...";
    });

    try {
      final sourceKeyPair = stellar.KeyPair.fromSecretSeed(_localSecretKey!);
      final sourceAccount = await _sdk.accounts.account(sourceKeyPair.accountId);

      final asset = stellar.Asset.createNonNativeAsset(customAssetCode, issuerAddress);
      final changeTrustOp = stellar.ChangeTrustOperationBuilder(asset, "99999999").build();

      final tx = stellar.TransactionBuilder(sourceAccount)
          .addOperation(changeTrustOp)
          .build();

      tx.sign(sourceKeyPair, stellar.Network.TESTNET);
      final response = await _sdk.submitTransaction(tx);

      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Trustline established successfully!")),
        );
        _fetchBalances();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to submit trustline transaction.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = "";
      });
    }
  }

  // Submit transfer or queue offline
  Future<void> _handleTransactionSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final toAddress = _toController.text.trim();
    final amount = _amountController.text.trim();
    final fromAddress = _localAccountId!;
    final currentTab = _activeTab;

    if (!_isOnline) {
      // Queue transaction locally
      final tx = StellarTransaction(
        fromAddress: fromAddress,
        toAddress: toAddress,
        amount: amount,
        assetCode: currentTab,
        timestamp: DateTime.now(),
        status: "Pending Sync",
      );
      await _dbHelper.addStellarTransaction(tx);
      _toController.clear();
      _amountController.clear();
      _loadTransactions();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offline: Transaction queued successfully!")),
      );
    } else {
      // Execute transaction on Stellar network
      await _executeTransaction(fromAddress, toAddress, amount, currentTab);
    }
  }

  Future<void> _executeTransaction(String from, String to, String amountStr, String assetType) async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Initiating Stellar payment...";
    });

    try {
      final sourceKeyPair = stellar.KeyPair.fromSecretSeed(_localSecretKey!);
      final sourceAccount = await _sdk.accounts.account(sourceKeyPair.accountId);

      final asset = assetType == "XLM"
          ? stellar.Asset.NATIVE
          : stellar.Asset.createNonNativeAsset(customAssetCode, issuerAddress);

      final paymentOp = stellar.PaymentOperationBuilder(to, asset, amountStr).build();

      final tx = stellar.TransactionBuilder(sourceAccount)
          .addOperation(paymentOp)
          .build();

      tx.sign(sourceKeyPair, stellar.Network.TESTNET);
      
      setState(() {
        _statusMessage = "Submitting transaction to Stellar network...";
      });
      final response = await _sdk.submitTransaction(tx);

      if (response.success) {
        final dbTx = StellarTransaction(
          fromAddress: from,
          toAddress: to,
          amount: amountStr,
          assetCode: assetType,
          timestamp: DateTime.now(),
          status: "Completed",
          txHash: response.hash,
        );
        await _dbHelper.addStellarTransaction(dbTx);
        _toController.clear();
        _amountController.clear();
        _loadTransactions();
        _fetchBalances();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payment Successful! Hash: ${response.hash}")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Transaction submission failed on-chain.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Payment failed: ${e.toString()}")),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _statusMessage = "";
      });
    }
  }

  // Sync offline transactions
  Future<void> _syncQueuedTransactions() async {
    final pending = _transactions.where((tx) => tx.status == "Pending Sync").toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pending transactions to sync.")),
      );
      return;
    }

    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot sync while offline.")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Syncing queued transactions...";
    });

    for (var tx in pending) {
      try {
        final sourceKeyPair = stellar.KeyPair.fromSecretSeed(_localSecretKey!);
        final sourceAccount = await _sdk.accounts.account(sourceKeyPair.accountId);

        final asset = tx.assetCode == "XLM"
            ? stellar.Asset.NATIVE
            : stellar.Asset.createNonNativeAsset(customAssetCode, issuerAddress);

        final paymentOp = stellar.PaymentOperationBuilder(tx.toAddress, asset, tx.amount).build();

        final stellarTx = stellar.TransactionBuilder(sourceAccount)
            .addOperation(paymentOp)
            .build();

        stellarTx.sign(sourceKeyPair, stellar.Network.TESTNET);
        final response = await _sdk.submitTransaction(stellarTx);

        if (response.success) {
          final updated = StellarTransaction(
            id: tx.id,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            amount: tx.amount,
            assetCode: tx.assetCode,
            timestamp: tx.timestamp,
            status: "Completed",
            txHash: response.hash,
          );
          await _dbHelper.updateStellarTransaction(updated);
        } else {
          final updated = StellarTransaction(
            id: tx.id,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            amount: tx.amount,
            assetCode: tx.assetCode,
            timestamp: tx.timestamp,
            status: "Failed",
          );
          await _dbHelper.updateStellarTransaction(updated);
        }
      } catch (e) {
        final updated = StellarTransaction(
          id: tx.id,
          fromAddress: tx.fromAddress,
          toAddress: tx.toAddress,
          amount: tx.amount,
          assetCode: tx.assetCode,
          timestamp: tx.timestamp,
          status: "Failed",
        );
        await _dbHelper.updateStellarTransaction(updated);
      }
    }

    _loadTransactions();
    _fetchBalances();
    setState(() {
      _isLoading = false;
      _statusMessage = "";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Sync complete!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = _transactions.any((tx) => tx.status == "Pending Sync");

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Stellar Horizon Wallet",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          Row(
            children: [
              Icon(
                _isOnline ? Icons.wifi : Icons.wifi_off,
                color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _isOnline ? "ONLINE" : "OFFLINE",
                style: TextStyle(
                  color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Switch(
                value: _isOnline,
                activeColor: Colors.greenAccent,
                inactiveThumbColor: Colors.redAccent,
                onChanged: (val) {
                  setState(() {
                    _isOnline = val;
                  });
                  _fetchBalances();
                },
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWalletCard(),
                const SizedBox(height: 20),
                _buildActionButtons(),
                const SizedBox(height: 20),
                _buildTransferForm(),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Transaction History",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (hasPending)
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _syncQueuedTransactions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.sync_problem, size: 16),
                        label: const Text("Sync Queued", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 15),
                _buildTransactionList(),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.blueAccent),
                    const SizedBox(height: 20),
                    Text(
                      _statusMessage.isNotEmpty ? _statusMessage : "Processing...",
                      style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade900.withOpacity(0.85), Colors.purple.shade900.withOpacity(0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(color: Colors.blueAccent.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.blur_circular, color: Colors.blueAccent, size: 36),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "STELLAR TESTNET",
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text("TOTAL BALANCE", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _xlmBalance.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              const Text("XLM", style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _creditsBalance.toStringAsFixed(2),
                style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              const Text("Credits", style: TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 20),
          const Text("PUBLIC ADDRESS", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  _localAccountId ?? "Generating...",
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white38, size: 18),
                onPressed: () {
                  if (_localAccountId != null) {
                    Clipboard.setData(ClipboardData(text: _localAccountId!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Address copied to clipboard")),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _fundWithFriendbot,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.monetization_on_outlined, color: Colors.blueAccent),
            label: const Text("Friendbot Faucet"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _hasTrustline ? null : _establishTrustline,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: _hasTrustline ? Colors.white30 : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: Icon(Icons.verified_user_outlined, color: _hasTrustline ? Colors.grey : Colors.greenAccent),
            label: Text(_hasTrustline ? "Trustline Active" : "Add Credits Asset"),
          ),
        ),
      ],
    );
  }

  Widget _buildTransferForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = "XLM"),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: _activeTab == "XLM" ? Colors.blueAccent : Colors.transparent, width: 2)),
                      ),
                      alignment: Alignment.center,
                      child: Text("Send XLM", style: TextStyle(color: _activeTab == "XLM" ? Colors.white : Colors.white38, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (!_hasTrustline) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please add the Credits asset trustline first.")),
                        );
                        return;
                      }
                      setState(() => _activeTab = "TranslateCredits");
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: _activeTab == "TranslateCredits" ? Colors.greenAccent : Colors.transparent, width: 2)),
                      ),
                      alignment: Alignment.center,
                      child: Text("Send Credits", style: TextStyle(color: _activeTab == "TranslateCredits" ? Colors.white : Colors.white38, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _toController,
              decoration: InputDecoration(
                labelText: "Recipient Address (G...)",
                labelStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return "Recipient is required";
                if (!val.trim().startsWith('G') || val.trim().length != 56) {
                  return "Invalid Stellar public key format";
                }
                return null;
              },
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: "Amount",
                labelStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return "Amount is required";
                final amt = double.tryParse(val.trim());
                if (amt == null || amt <= 0) return "Must be a positive number";
                return null;
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _handleTransactionSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _activeTab == "XLM" ? Colors.blueAccent : Colors.greenAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _isOnline ? "Send Transaction Now" : "Queue Transaction Offline",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        child: const Text("No transactions recorded yet.", style: TextStyle(color: Colors.white24)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final isSent = tx.fromAddress == _localAccountId;
        
        Color statusColor = Colors.greenAccent;
        if (tx.status == "Pending Sync") statusColor = Colors.amberAccent;
        if (tx.status == "Failed") statusColor = Colors.redAccent;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.02)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSent ? Colors.redAccent.withOpacity(0.1) : Colors.greenAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSent ? Icons.arrow_outward : Icons.arrow_downward,
                  color: isSent ? Colors.redAccent : Colors.greenAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSent ? "Sent To: ${tx.toAddress.substring(0, 8)}..." : "Received From: ${tx.fromAddress.substring(0, 8)}...",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM dd, HH:mm:ss').format(tx.timestamp),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${isSent ? '-' : '+'}${tx.amount} ${tx.assetCode}",
                    style: TextStyle(
                      color: isSent ? Colors.white : Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tx.status.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
