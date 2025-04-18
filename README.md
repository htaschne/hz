# HuffmanCompressor

**HuffmanCompressor** is a simple macOS application built with Swift 6.1 that demonstrates how to compress and decompress files using the **Huffman Coding** algorithm.

⚠️ **This app is intended for educational purposes only.** It is currently **slower** and **less efficient** than modern compression utilities like ZIP, and **should not** be used in production environments or for critical file handling.

## ✨ Features

- 📦 Compress any file using the Huffman algorithm
- 📂 Decompress previously compressed `.huff` files
- 🔍 View compression statistics and tree structure (optional in debug mode)
- 🎓 Great for studying how lossless entropy-based compression works

## 🧠 Why Huffman?

Huffman coding is a classic lossless data compression algorithm. While no longer optimal compared to modern codecs, it’s widely used as an educational introduction to entropy encoding.

## 🚀 Getting Started

### Requirements

- macOS 12.0 or later
- Xcode 15 or later
- Swift 6.1

### Installation

Clone the repository and open the Xcode project:

```bash
git clone https://github.com/yourusername/HuffmanCompressor.git
cd HuffmanCompressor
open HuffmanCompressor.xcodeproj
