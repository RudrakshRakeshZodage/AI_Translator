import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as stellar;

import '../../core/blockchain/stellar_service.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/models.dart';

class StellarTransactionScreen extends StatefulWidget {
  const StellarTransactionScreen({super.key});

  @override
  State<StellarTransactionScreen> createState() => _StellarTransactionScreenState();
}

class _StellarTransactionScreenState extends State<StellarTransactionScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final StellarService _stellarService = StellarService();
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _amountController = TextEditingController();
  final _secretKeyController = TextEditingController();

  // Stellar Mainnet Contract Config
  static const String translateCreditsContractId =
      "CB2VC4KBEHANNPJR6TYONOXX6LYSODIAYJ37HZCC6X4BYORSRXLKGP67";
  static const String giftVoucherContractId =
      "CAPEI5YTCN3BRP6FHWDM467M5Y2YWKTM6CUYHI23UYRRYJJITKPT3GCX";

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

  Future<void> _fetchBalances() async {
    if (_localAccountId == null) return;

    if (!_isOnline) {
      return; // Keep cached balance when offline
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final xlm = await _stellarService.getXlmBalance(_localAccountId!);
      final credits = await _stellarService.getCreditsBalance(_localAccountId!);

      if (mounted) {
        setState(() {
          _xlmBalance = xlm;
          _creditsBalance = credits;
          _hasTrustline = credits > 0 || xlm > 0;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTransactions() async {
    final list = await _dbHelper.getStellarTransactions();
    if (mounted) {
      setState(() {
        _transactions = list;
      });
    }
  }

  // Setup trustline on Stellar Mainnet for TranslateCredits
  Future<void> _establishTrustline() async {
    if (!_isOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot establish trustline offline.")),
      );
      return;
    }

    if (_localSecretKey == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Establishing Mainnet trustline...";
    });

    try {
      final success = await _stellarService.setupTrustline(_localSecretKey!);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mainnet Trustline established successfully!")),
        );
        _fetchBalances();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to establish Mainnet trustline.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = "";
        });
      }
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offline: Transaction queued locally!")),
      );
    } else {
      // Execute transaction on Stellar Mainnet
      await _executeTransaction(fromAddress, toAddress, amount, currentTab);
    }
  }

  Future<void> _executeTransaction(String from, String to, String amountStr, String assetType) async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Initiating Stellar Mainnet transfer...";
    });

    try {
      final double amt = double.parse(amountStr);
      String? txHash;

      if (assetType == "TranslateCredits") {
        txHash = await _stellarService.transferCredits(_localSecretKey!, to, amt);
      } else {
        // Native XLM Mainnet transfer
        final sourceKeyPair = stellar.KeyPair.fromSecretSeed(_localSecretKey!);
        final sourceAccount = await _sdk.accounts.account(sourceKeyPair.accountId);
        final paymentOp = stellar.PaymentOperationBuilder(to, stellar.Asset.NATIVE, amountStr).build();

        final tx = stellar.TransactionBuilder(sourceAccount)
            .addOperation(paymentOp)
            .build();

        tx.sign(sourceKeyPair, stellar.Network.PUBLIC);
        final response = await _sdk.submitTransaction(tx);
        if (response.success) {
          txHash = response.hash;
        }
      }

      if (!mounted) return;

      if (txHash != null) {
        final dbTx = StellarTransaction(
          fromAddress: from,
          toAddress: to,
          amount: amountStr,
          assetCode: assetType,
          timestamp: DateTime.now(),
          status: "Completed",
          txHash: txHash,
        );
        await _dbHelper.addStellarTransaction(dbTx);
        _toController.clear();
        _amountController.clear();
        _loadTransactions();
        _fetchBalances();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Mainnet Transfer Successful! Hash: $txHash")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mainnet transaction submission failed.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Payment failed: ${e.toString()}")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = "";
        });
      }
    }
  }

  // Sync offline transactions with Soroban Mainnet
  Future<void> _syncQueuedTransactions() async {
    final pending = _transactions.where((tx) => tx.status == "Pending Sync").toList();
    if (pending.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pending transactions to sync.")),
      );
      return;
    }

    if (!_isOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot sync while offline.")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Syncing queued transactions to Soroban Mainnet...";
    });

    for (var tx in pending) {
      try {
        final double amt = double.tryParse(tx.amount) ?? 0.0;
        final txHash = await _stellarService.syncOfflineUsageRecord(
          userSecret: _localSecretKey!,
          recordIdHex: _stellarService.sha256Hash("${tx.fromAddress}:${tx.timestamp}"),
          amount: amt,
          timestamp: tx.timestamp.millisecondsSinceEpoch ~/ 1000,
          expiry: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400,
          nonce: await _stellarService.getUserOnChainNonce(_localAccountId!) + 1,
        );

        if (txHash != null) {
          final updated = StellarTransaction(
            id: tx.id,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            amount: tx.amount,
            assetCode: tx.assetCode,
            timestamp: tx.timestamp,
            status: "Completed",
            txHash: txHash,
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
      } catch (_) {
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
    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusMessage = "";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mainnet Sync complete!")),
      );
    }
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
          "Stellar Soroban Mainnet",
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
                activeThumbColor: Colors.greenAccent,
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
                const SizedBox(height: 16),
                _buildContractInfoCard(),
                const SizedBox(height: 16),
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
          colors: [Colors.blue.shade900.withValues(alpha: 0.85), Colors.purple.shade900.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))
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
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "STELLAR MAINNET / SOROBAN",
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

  Widget _buildContractInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 18),
              SizedBox(width: 8),
              Text(
                "SOROBAN MAINNET SMART CONTRACTS",
                style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text("translate_credits:", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SelectableText(
            translateCreditsContractId,
            style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          const Text("gift_voucher:", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SelectableText(
            giftVoucherContractId,
            style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
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
            onPressed: _hasTrustline ? null : _establishTrustline,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: _hasTrustline ? Colors.white30 : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: Icon(Icons.verified_user_outlined, color: _hasTrustline ? Colors.grey : Colors.greenAccent),
            label: Text(_hasTrustline ? "Trustline Active" : "Add Mainnet Asset"),
          ),
        ),
      ],
    );
  }

  Widget _buildTransferForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                    onTap: () => setState(() => _activeTab = "TranslateCredits"),
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
                _isOnline ? "Send Transaction Now (Mainnet)" : "Queue Transaction Offline",
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
            color: const Color(0xFF1E293B).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSent ? Colors.redAccent.withValues(alpha: 0.1) : Colors.greenAccent.withValues(alpha: 0.1),
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
                      isSent ? "To: ${tx.toAddress.substring(0, 8)}..." : "From: ${tx.fromAddress.substring(0, 8)}...",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM dd, yyyy - hh:mm a').format(tx.timestamp),
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
                      color: isSent ? Colors.redAccent : Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tx.status,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
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
