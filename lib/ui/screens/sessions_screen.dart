import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/models.dart';
import 'home_screen.dart';
import 'stellar_transaction_screen.dart';


class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}


class _SessionsScreenState extends State<SessionsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<TranslationSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await _dbHelper.getSessions();
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  void _createNewSession() async {
    final title = "Talk ${DateFormat('MMM dd, HH:mm').format(DateTime.now())}";
    final sessionId = await _dbHelper.createSession(title);
    if (!mounted) return;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(sessionId: sessionId, sessionTitle: title),
      ),
    );
    _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withOpacity(0.1),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              _buildSliverAppBar(),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: _isLoading
                    ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                    : _sessions.isEmpty
                        ? SliverFillRemaining(child: _buildEmptyState())
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildSessionCard(_sessions[index]),
                              childCount: _sessions.length,
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewSession,
        backgroundColor: Colors.blueAccent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 180.0,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF0F172A),
      actions: [
        IconButton(
          icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.blueAccent),
          tooltip: "Stellar Wallet",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StellarTransactionScreen()),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: const Text(
          "My Talks",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 24,
            fontFamily: 'sans-serif',
          ),
        ),
        background: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Keep track of your offline conversations.",
                style: TextStyle(color: Colors.white38, fontSize: 13, fontFamily: 'sans-serif'),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.chat_bubble_outline_rounded, size: 60, color: Colors.white10),
        ),
        const SizedBox(height: 24),
        const Text(
          "Quiet here, isn't it?",
          style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'sans-serif'),
        ),
        const SizedBox(height: 8),
        const Text(
          "Start a translation session to begin.",
          style: TextStyle(color: Colors.white24, fontSize: 14, fontFamily: 'sans-serif'),
        ),
      ],
    );
  }

  Widget _buildSessionCard(TranslationSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            title: Text(
              session.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16, fontFamily: 'sans-serif'),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                DateFormat('EEEE, MMM dd • HH:mm').format(session.createdAt),
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 0.5, fontFamily: 'sans-serif'),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HomeScreen(sessionId: session.id!, sessionTitle: session.title),
                ),
              );
              _loadSessions();
            },
          ),
        ),
      ),
    ),
  );
}
}
