<p align="center">
  <img src="https://raw.githubusercontent.com/htaschne/hz/refs/heads/main/hz/Assets.xcassets/AppIcon.appiconset/512.png" alt="Hz icon"/>
</p>

**HuffmanZip (Hz)** is a simple macOS application built with Swift 6.1 that demonstrates how to compress and decompress files using the [Huffman Coding algorithm](https://en.wikipedia.org/wiki/Huffman_coding).

## ⚠️ Disclaimer
This project is provided for educational purposes only. It is not optimized for performance or real-world use. Use at your own risk.


## ✨ Features

- [x] 📦 Compress any file using the Huffman algorithm
- [x] 📂 Decompress previously compressed `.hz` files



## 🧠 Why Huffman?

Huffman coding is a classic lossless data compression algorithm. While no longer optimal compared to modern codecs, it’s widely used as an educational introduction to entropy encoding.

## 🚀 Getting Started

### Requirements

- macOS 15.4.1 or later
- Xcode 16.3 or later
- Swift 6.1

### Installation

Clone the repository and open the Xcode project:

```bash
git clone https://github.com/htaschne/hz.git
cd hz
open hz.xcodeproj
```

### Demo
Although it's way slower than state of the art compressors it compresses the bible in under a second and takes 2s to decompress it

<p align="center">
  <img src="https://raw.githubusercontent.com/htaschne/hz/refs/heads/main/media/hz-demo.gif" alt="Gif of Hz app demo"/>
</p>
