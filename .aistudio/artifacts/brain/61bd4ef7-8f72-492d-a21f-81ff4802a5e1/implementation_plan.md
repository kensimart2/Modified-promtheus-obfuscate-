# Implementation Plan: Ultra-Hardened Layer 2 Obfuscation & Compact Size Optimization

Rencana peningkatan proteksi Layer 2 (Luraph-style loader & packer) agar sangat tangguh terhadap reverse engineering dan memory dumping, sekaligus mengoptimalkan algoritma kompresi agar ukuran output terkendali stabil di kisaran 100KB (selalu di bawah batas 130KB) dalam format 1 baris utuh.

## 1. Arsitektur Multi-Stage Rolling Cipher & Dynamic State Permutation
- **Kelemahan Saat Ini**: Keystream XOR satu putaran dapat dianalisis secara linear jika cracker berhasil membaca konstanta kunci `_K`.
- **Peningkatan Proteksi**:
  - **Cascading 3-Round Feistel/Rolling Cipher**: Payload didekripsi melalui tiga tahap transformasi interaktif (Linear Congruential Generator + non-linear S-box rotation + variable-distance rolling transposition).
  - **Dynamic State Permutation**: Keystream terus bergulir (*rolling*) bergantung pada byte sebelumnya (*Cipher Feedback*), sehingga ekstraksi sebagian tidak dapat merekonstruksi keseluruhan payload.
  - **Key Masking di Metatable Root**: Konstanta `_K` dipecah menjadi polinomial dinamis yang dihitung saat runtime menggunakan metatable dispatcher primitif, menghindarkan integer literal sederhana dari pencarian statis.

## 2. Verifikasi Integritas Loader & Silent Memory Poisoning Anti-Dump
- **Deteksi Hooking & Sandboxing**:
  - Memeriksa integritas fungsi inti runtime Luau (`string.byte`, `table.concat`, `loadstring`, `bit32.bxor`).
  - Mendeteksi hooking fungsi global (`print`, `loadstring`), interceptor debug (`debug.getinfo`, `debug.gethook`), modifikasi closure environment, serta validasi integritas C-closure native Luau.
- **Mekanisme Reaksi Silent Fail**:
  - Sesuai preferensi, loader **tidak akan memicu crash kentara atau error message** yang memberi tahu cracker bahwa hook terdeteksi.
  - Sebagai gantinya, loader akan secara senyap **merusak seed dekripsi (*state poisoning*)** dan mengubah tabel lookup menjadi nilai semu.
  - Akibatnya, byte stream Layer 1 yang didekripsi menjadi kode acak tak bermakna (*garbage bytecode*), menggagalkan alat deobfuscate otomatis tanpa memberi petunjuk alasan kegagalan.

## 3. Kompresi Adaptif LZSS & Base91 Stream (Kontrol Ukuran ~100KB)
- **Problem Ukuran (>130KB)**:
  - Prometheus VM Layer 1 mengandung banyak perulangan instruksi dispatcher. Jika kompresi tidak agresif, representasi ASCII akan membengkak mendekati atau melebihi 130KB.
- **Strategi Optimasi Ukuran**:
  - **Enhanced Sliding Hash Chain (Window 4096 / Match Max 255)**: Memperdalam kedalaman pencarian match chain untuk menangkap token berulang lebih panjang dalam dispatcher VM Prometheus.
  - **High-Density Base91/Base85 Encoding**: Menggunakan karakter printable ASCII aman tanpa karakter bracket `]` atau backslash `\`.
  - **Kamus Substitusi Frekuensi Karakter `kH` Adaptif**: Mengidentifikasi chunk 4-karakter yang paling sering muncul di dalam stream biner terenkripsi dan menggantikannya dengan penanda tunggal sebelum serialisasi.
  - **Target Ukuran**: Memastikan skrip besar terkompresi stabil di kisaran 90KB - 105KB (maksimal di bawah 120KB, jauh di bawah 130KB).

## 4. Format Output Monolithic 1 Baris Utuh
- Seluruh loader Layer 2, kamus `kH`, stream `XH`, dan handler dispatch tetap disatukan menjadi **1 baris tunggal (*single-line unbroken*)** tanpa karakter newline (`\n`), indentasi (`\t`), atau komentar (`--`).
- Menjamin kemudahan pemakaian langsung di executor Roblox Luau tanpa kendala pemotongan baris.

## 5. Rencana Pengujian & Validasi
- **Ukuran File**: Verifikasi otomatis bahwa output skrip kompleks berada di kisaran ~100KB dan tidak melampaui batas 120KB.
- **Single-Line**: Memastikan string output tidak mengandung karakter newline (`\n`) dan berupa 1 baris utuh.
- **Keamanan Anti-Dump**: Menguji bahwa lingkungan dengan intercepted `loadstring` atau proxy hooked globals mengalami *silent poison* tanpa mengekspos payload Layer 1.
- **Kompatibilitas Luau**: Menjalankan pengujian 100% pada runner Vitest dan simulator runtime Luau Roblox untuk menjamin eksekusi fungsional normal tetap akurat tanpa bug.
