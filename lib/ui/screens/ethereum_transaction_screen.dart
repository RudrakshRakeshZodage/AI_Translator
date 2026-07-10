import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:web3dart/web3dart.dart';

import '../../core/database/database_helper.dart';
import '../../core/models/models.dart';

class EthereumTransactionScreen extends StatefulWidget {
  const EthereumTransactionScreen({super.key});

  @override
  State<EthereumTransactionScreen> createState() => _EthereumTransactionScreenState();
}

class _EthereumTransactionScreenState extends State<EthereumTransactionScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _amountController = TextEditingController();
  final _privateKeyController = TextEditingController();

  // Network State
  bool _isOnline = true;
  String _rpcUrl = "https://ethereum-sepolia-rpc.publicnode.com";
  late Web3Client _ethClient;

  // Wallet State
  String _walletType = "local"; // "local" or "metamask"
  bool _isMetaMaskConnected = false;
  String _metaMaskAddress = "0x71C7656EC7ab88b098defB751B7401B5f6d8976F";
  double _metaMaskBalance = 5.42;

  String? _localPrivateKey;
  String? _localAddress;
  double _localBalance = 0.0;
  double _mockBalanceOffset = 0.0; // Tracks sandbox faucet top-ups offline

  List<EthTransaction> _transactions = [];
  bool _isLoading = false;
  String _statusMessage = "";

  @override
  void initState() {
    super.initState();
    _ethClient = Web3Client(_rpcUrl, http.Client());
    _loadLocalWallet();
    _loadTransactions();
  }

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    _privateKeyController.dispose();
    _ethClient.dispose();
    super.dispose();
  }

  // Load or generate local wallet
  void _loadLocalWallet() {
    // Generate a random key for the user to start with if none exists
    final random = Random.secure();
    final credentials = EthPrivateKey.createRandom(random);
    _localPrivateKey = bytesToHex(credentials.privateKey);
    _localAddress = credentials.address.hex;
    _privateKeyController.text = _localPrivateKey!;
    _fetchBalance();
  }

  void _importPrivateKey(String privateKeyHex) {
    try {
      final credentials = EthPrivateKey.fromHex(privateKeyHex.trim());
      setState(() {
        _localPrivateKey = privateKeyHex.trim();
        _localAddress = credentials.address.hex;
        _mockBalanceOffset = 0.0; // Reset mock top-up on new import
      });
      _fetchBalance();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Wallet imported successfully!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid Private Key Hex format.")),
      );
    }
  }

  Future<void> _fetchBalance() async {
    if (_walletType == "metamask" && _isMetaMaskConnected) {
      return;
    }
    if (_localAddress == null) return;

    if (!_isOnline) {
      // Offline fallback
      setState(() {
        _localBalance = 0.0 + _mockBalanceOffset;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final balance = await _ethClient.getBalance(EthereumAddress.fromHex(_localAddress!));
      if (mounted) {
        setState(() {
          _localBalance = balance.getValueInUnit(EtherUnit.ether) + _mockBalanceOffset;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localBalance = 0.0 + _mockBalanceOffset;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTransactions() async {
    final list = await _dbHelper.getEthTransactions();
    setState(() {
      _transactions = list;
    });
  }

  // Simulated MetaMask connection
  void _connectMetaMask() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Connecting MetaMask...";
    });
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _isMetaMaskConnected = true;
      _isLoading = false;
      _statusMessage = "";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("MetaMask Connected!")),
    );
  }

  // Sandbox top-up faucet
  void _topUpSandbox() {
    setState(() {
      _mockBalanceOffset += 1.0;
      if (_walletType == "local") {
        _localBalance += 1.0;
      } else {
        _metaMaskBalance += 1.0;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Sandbox Faucet: +1.0 Sepolia ETH credited!")),
    );
  }

  // Queue transaction offline or execute online
  Future<void> _handleTransactionSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final toAddress = _toController.text.trim();
    final amount = _amountController.text.trim();
    final fromAddress = _walletType == "local" ? _localAddress! : _metaMaskAddress;

    if (!_isOnline) {
      // Offline Queue Mode
      final tx = EthTransaction(
        fromAddress: fromAddress,
        toAddress: toAddress,
        amount: amount,
        timestamp: DateTime.now(),
        status: "Pending Sync",
      );
      await _dbHelper.addEthTransaction(tx);
      _toController.clear();
      _amountController.clear();
      _loadTransactions();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offline: Transaction queued successfully!")),
      );
    } else {
      // Online execution
      await _executeTransaction(fromAddress, toAddress, amount);
    }
  }

  Future<void> _executeTransaction(String from, String to, String amountStr) async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Initiating transaction...";
    });

    try {
      final amountWei = BigInt.from(double.parse(amountStr) * 1e18);

      if (_walletType == "local" && _localPrivateKey != null) {
        setState(() {
          _statusMessage = "Signing transaction locally...";
        });
        final credentials = EthPrivateKey.fromHex(_localPrivateKey!);

        setState(() {
          _statusMessage = "Broadcasting to Sepolia testnet...";
        });
        final txHash = await _ethClient.sendTransaction(
          credentials,
          Transaction(
            to: EthereumAddress.fromHex(to),
            value: EtherAmount.fromUnitAndValue(EtherUnit.wei, amountWei),
          ),
          chainId: 11155111, // Sepolia Chain ID
        );

        final tx = EthTransaction(
          fromAddress: from,
          toAddress: to,
          amount: amountStr,
          timestamp: DateTime.now(),
          status: "Completed",
          txHash: txHash,
        );
        await _dbHelper.addEthTransaction(tx);
        _toController.clear();
        _amountController.clear();
        _loadTransactions();
        _fetchBalance();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Success! Tx Hash: $txHash")),
        );
      } else {
        // MetaMask simulated execution
        setState(() {
          _statusMessage = "Requesting MetaMask signature...";
        });
        await Future.delayed(const Duration(seconds: 1));
        final txHash = "0x" + List.generate(64, (i) => Random().nextInt(16).toRadixString(16)).join();

        final tx = EthTransaction(
          fromAddress: from,
          toAddress: to,
          amount: amountStr,
          timestamp: DateTime.now(),
          status: "Completed",
          txHash: txHash,
        );
        await _dbHelper.addEthTransaction(tx);
        _toController.clear();
        _amountController.clear();
        setState(() {
          _metaMaskBalance -= double.parse(amountStr);
        });
        _loadTransactions();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("MetaMask Success! Tx Hash: $txHash")),
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
        final amountWei = BigInt.from(double.parse(tx.amount) * 1e18);

        if (_walletType == "local" && _localPrivateKey != null) {
          final credentials = EthPrivateKey.fromHex(_localPrivateKey!);
          final txHash = await _ethClient.sendTransaction(
            credentials,
            Transaction(
              to: EthereumAddress.fromHex(tx.toAddress),
              value: EtherAmount.fromUnitAndValue(EtherUnit.wei, amountWei),
            ),
            chainId: 11155111,
          );

          final updated = EthTransaction(
            id: tx.id,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            amount: tx.amount,
            timestamp: tx.timestamp,
            status: "Completed",
            txHash: txHash,
          );
          await _dbHelper.updateEthTransaction(updated);
        } else {
          // Simulated sync
          final txHash = "0x" + List.generate(64, (i) => Random().nextInt(16).toRadixString(16)).join();
          final updated = EthTransaction(
            id: tx.id,
            fromAddress: tx.fromAddress,
            toAddress: tx.toAddress,
            amount: tx.amount,
            timestamp: tx.timestamp,
            status: "Completed",
            txHash: txHash,
          );
          await _dbHelper.updateEthTransaction(updated);
        }
      } catch (e) {
        final updated = EthTransaction(
          id: tx.id,
          fromAddress: tx.fromAddress,
          toAddress: tx.toAddress,
          amount: tx.amount,
          timestamp: tx.timestamp,
          status: "Failed",
        );
        await _dbHelper.updateEthTransaction(updated);
      }
    }

    _loadTransactions();
    _fetchBalance();
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
    final currentAddress = _walletType == "local" ? (_localAddress ?? "") : _metaMaskAddress;
    final currentBalance = _walletType == "local" ? _localBalance : _metaMaskBalance;
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
          "Ethereum Sepolia",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Network Switch (Simulate Online/Offline)
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
                  fontSize: 10,
                  color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
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
                  _fetchBalance();
                },
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selector
                Row(
                  children: [
                    Expanded(
                      child: _buildSelectorTab("local", "Local Wallet", Icons.security),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSelectorTab("metamask", "MetaMask", Icons.account_balance_wallet_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Card info
                if (_walletType == "metamask" && !_isMetaMaskConnected)
                  _buildMetaMaskConnectCard()
                else
                  _buildWalletCard(currentAddress, currentBalance),

                const SizedBox(height: 24),

                // Private key importer for local wallet
                if (_walletType == "local") ...[
                  _buildPrivateKeyImporter(),
                  const SizedBox(height: 24),
                ],

                // Send transaction form
                if (_walletType == "local" || _isMetaMaskConnected) ...[
                  _buildSendForm(),
                  const SizedBox(height: 24),
                ],

                // Queue and History Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Transactions History",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (hasPending)
                      ElevatedButton.icon(
                        onPressed: _isOnline ? _syncQueuedTransactions : null,
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text("Sync Queue"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTransactionList(),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.blueAccent),
                    const SizedBox(height: 20),
                    Text(
                      _statusMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectorTab(String type, String label, IconData icon) {
    final active = _walletType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _walletType = type;
        });
        _fetchBalance();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.blueAccent.withOpacity(0.15) : const Color(0xFF1E293B).withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? Colors.blueAccent : Colors.white.withOpacity(0.05),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.blueAccent : Colors.white60, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletCard(String address, double balance) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueAccent.withOpacity(0.2), const Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _walletType == "local" ? "LOCAL SECURE WALLET" : "METAMASK CONNECTED",
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                onPressed: _fetchBalance,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "Account Balance",
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                balance.toStringAsFixed(4),
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              const Text(
                "ETH",
                style: TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            "Wallet Address",
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  address,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Address copied to clipboard!")),
                  );
                },
                child: const Icon(Icons.copy, color: Colors.white30, size: 16),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _topUpSandbox,
                  icon: const Icon(Icons.water_drop_outlined, size: 16),
                  label: const Text("Sandbox Faucet (+1.0)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.05),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaMaskConnectCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.orangeAccent),
          const SizedBox(height: 16),
          const Text(
            "MetaMask Wallet Integration",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Connect your MetaMask to manage balances and authorize transactions securely.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _connectMetaMask,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Connect MetaMask", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateKeyImporter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Import Private Key",
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _privateKeyController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: "Enter Private Key hex",
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _importPrivateKey(_privateKeyController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  foregroundColor: Colors.white,
                ),
                child: const Text("Import"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendForm() {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Send Transaction",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _toController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: "Recipient Address (0x...)",
                labelStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return "Please enter recipient address";
                if (!val.startsWith("0x") || val.length != 42) return "Invalid address format";
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: "Amount (ETH)",
                labelStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return "Please enter amount";
                if (double.tryParse(val) == null || double.parse(val) <= 0) return "Enter valid amount";
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleTransactionSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _isOnline ? "Send Transaction" : "Queue Transaction (Offline)",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
        padding: const EdgeInsets.all(30),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          "No transaction history",
          style: TextStyle(color: Colors.white24, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final isPending = tx.status == "Pending Sync";
        final isFailed = tx.status == "Failed";

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPending
                  ? Colors.orangeAccent.withOpacity(0.2)
                  : isFailed
                      ? Colors.redAccent.withOpacity(0.2)
                      : Colors.greenAccent.withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPending
                      ? Colors.orangeAccent.withOpacity(0.1)
                      : isFailed
                          ? Colors.redAccent.withOpacity(0.1)
                          : Colors.greenAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPending
                      ? Icons.sync
                      : isFailed
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                  color: isPending
                      ? Colors.orangeAccent
                      : isFailed
                          ? Colors.redAccent
                          : Colors.greenAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "To: ${tx.toAddress.substring(0, 8)}...${tx.toAddress.substring(34)}",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM dd, HH:mm').format(tx.timestamp),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    if (tx.txHash != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Hash: ${tx.txHash!.substring(0, 10)}...",
                        style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "-${tx.amount} ETH",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPending
                          ? Colors.orangeAccent.withOpacity(0.15)
                          : isFailed
                              ? Colors.redAccent.withOpacity(0.15)
                              : Colors.greenAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tx.status.toUpperCase(),
                      style: TextStyle(
                        color: isPending
                            ? Colors.orangeAccent
                            : isFailed
                                ? Colors.redAccent
                                : Colors.greenAccent,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
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
