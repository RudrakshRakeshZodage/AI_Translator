# <img src="assets/logo.png" width="36" height="36" /> BHARAT KI AWAAZ: The Offline-First AI Translator & Web3 Wallet

BHARAT KI AWAAZ is a high-performance, **Offline-First** AI translation application built with Flutter and C++. It leverages on-device AI models (Whisper and Gemma) to provide secure, real-time multilingual communication alongside a fully integrated offline-ready Web3 Ethereum wallet.

It uses a custom **C++ Native Memory Bridge** for stable SIMD performance and a sophisticated **SQLite synchronization engine** to cache, queue, and sync blockchain transactions with zero internet dependency.

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat-square&logo=flutter&logoColor=white) ![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=flat-square&logo=dart&logoColor=white) ![C++](https://img.shields.io/badge/C++-%2300599C.svg?style=flat-square&logo=c%2B%2B&logoColor=white) ![SQLite](https://img.shields.io/badge/SQLite-%2307405E.svg?style=flat-square&logo=sqlite&logoColor=white) ![Ethereum](https://img.shields.io/badge/Ethereum-3C3C3D?style=flat-square&logo=ethereum&logoColor=white) ![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## 📸 Feature Showcase

| Splash | Connect MetaMask | Onboarding | Dashboard | History | Offline Translation |
| :---: | :---: | :---: | :---: | :---: | :---: |
| <img src="screenshots/1.jpg" width="150" /> | <img src="screenshots/2.jpg" width="150" /> | <img src="screenshots/3.jpg" width="150" /> | <img src="screenshots/4.jpg" width="150" /> | <img src="screenshots/6.jpg" width="150" /> | <img src="screenshots/7.jpg" width="150" /> |

---

## 🔄 Transaction Lifecycle & Sync Logic

This sequence diagram illustrates how transactions are optimistically updated in the UI, stored locally in SQLite when offline, processed by the queue synchronization runner, signed, and broadcasted to the Sepolia testnet once an internet connection is established.

```mermaid
sequenceDiagram
    participant User as User (UI)
    participant DB as SQLite (Local)
    participant QP as Queue Processor
    participant Web3 as Sepolia RPC (Node)

    User->>DB: 1. Initiate Transaction (Status: Pending Sync)
    Note over User, DB: Instant UI Update (Optimistic/Pending)

    QP->>DB: 2. Poll Transactions Queue Table
    
    alt If Network is Offline
        QP->>DB: 3. Retain status as 'Pending Sync'
    else If Network is Online
        QP->>QP: 4. Extract & Sign Transaction with Private Key
        QP->>Web3: 5. POST /eth_sendRawTransaction
        Web3-->>QP: 6. Return Transaction Hash (txHash)
        QP->>DB: 7. Update status to 'Completed' + store txHash
        DB-->>User: 8. UI Sync (Refreshes list to COMPLETED)
    end

    loop Background Sync (Every 10s)
        QP->>DB: 9. Fetch all 'Pending Sync' transactions
        QP->>QP: 10. Check Internet Connectivity status
        QP->>Web3: 11. Broadcast & sync outstanding queue
        QP->>DB: 12. Update statuses in local storage
    end
```


## 🛠️ Detailed Technology Stack

### 📱 Frontend & UI
- **Framework**: [Flutter](https://flutter.dev/) (3.x)
- **Language**: [Dart](https://dart.dev/)
- **State Management**: Reactive Streams & ChangeNotifiers
- **Async Processing**: Dart Isolates (Multi-threading for AI workloads)

### 🏗️ Native Bridge (The Core)
- **Language**: C++17
- **Interoperability**: [Dart FFI](https://dart.dev/guides/libraries/c-interop) (Foreign Function Interface)
- **Logging**: Android Native `liblog` (utilizing `__android_log_print`)
- **Memory Management**: POSIX-standard `malloc`/`free` with hardened pointer tagging for Android 14+

### 🤖 Artificial Intelligence Models
- **Speech-to-Text**: [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) 
  - *Model*: Base (Multilingual)
  - *Sampling*: Greedy decoding for real-time responsiveness
- **Translation (LLM)**: [Gemma 2B](https://ai.google.dev/gemma)
  - *Quantization*: 4-bit (Q4_K_M) for high-speed mobile execution
  - *Format*: GGUF (GGML Universal File)

### 🌐 Web3 & Blockchain (Ethereum)
- **Library**: `web3dart` & `http`
- **Network**: Ethereum Sepolia Testnet (Chain ID: `11155111`)
- **RPC Endpoint**: `https://ethereum-sepolia-rpc.publicnode.com`
- **Offline Storage**: SQLite database for caching pending transactions and offline history

### ⚡ Hardware Acceleration & Build
- **Instruction Set**: ARMv8-A (64-bit)
- **SIMD Engine**: [ARM NEON](https://developer.arm.com/architectures/instruction-sets/simd-isas/neon) (Stabilized with Goldilocks Patch)
- **Build System**: CMake 3.22+
- **Compiler**: Clang++ (via Android NDK r26b)
- **Platform**: Android SDK 24+ (Vulkan-ready)

## ⚡ Performance Optimization & Stability

### 1. The "Goldilocks" Stability Patch
To ensure maximum speed without the common `SIGSEGV` crashes on modern Snapdragon chips (like the Vivo T3x), we implemented a custom header-level stability patch. This allows the engine to use **ARM NEON** for 50x speed while safely disabling problematic extensions (SVE/DOTPROD) that cause hardware-level faults.

### 2. Dynamic 90% Spec Utilization
The application dynamically detects the hardware specifications of the host device. It automatically calculates the optimal thread count using the formula:
`Threads = Max(1, Hardware_Cores - 1)`
This ensures the app utilizes **~90% of the device's raw power** while keeping the UI thread smooth and responsive.

### 3. Memory Integrity Bridge
We use a hardened "Fortress Mode" memory bridge. Audio data is converted from Dart's `Double` precision to C++ `Float` using direct system allocation (`malloc`), preventing memory corruption and ensuring perfect data alignment for the AI's mathematical kernels.

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (latest)
- Android NDK (r26+)
- AI Models (GGUF format) placed in:
  `/data/user/0/com.antigravity.ai_translator/app_flutter/models/`

### Build Instructions
```bash
# 1. Clean the build cache to ensure NEON flags are applied
flutter clean

# 2. Build and Run on your device
flutter run --release
```

## 📁 Project Structure

- `lib/`: Flutter UI and Core AI Logic.
- `src/`: Native C++ Bridge and AI Engine integrations.
- `android/app/CMakeLists.txt`: Hardware acceleration and SIMD configuration.

---
Built with 💙 for the next generation of private communication.
