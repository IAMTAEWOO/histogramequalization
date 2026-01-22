# Streaming Histogram Equalization Core (RTL)

This repository presents a **fully streaming hardware implementation of Histogram Equalization (HE)** for grayscale images.
The design is written in synthesizable Verilog and verified against a C reference model using a self-checking testbench.

Unlike conventional frame-based HE implementations, this design **eliminates frame buffers** and processes pixels in a streaming manner with **one pixel per cycle throughput**.

---

## Key Features
- Fully streaming architecture (no frame buffer)
- One pixel per cycle throughput after pipeline fill
- Valid/Ready handshake-based flow control
- Parameterized image resolution (WIDTH × HEIGHT)
- Synthesizable Verilog RTL
- Bit-accurate C reference model for verification

---

## Architecture Overview

The HE pipeline is divided into four stages:

1. **Histogram Accumulation**  
   Incoming grayscale pixels update histogram bins in a streaming manner.

2. **CDF Computation**  
   After frame end, the cumulative distribution function (CDF) is computed sequentially.

3. **LUT Generation**  
   A lookup table is generated based on the normalized CDF.

4. **Streaming Pixel Remapping**  
   Incoming pixels are remapped using the LUT without buffering the full frame.

The entire system is controlled by an FSM with deterministic latency.

---

## Interface

### Input
- `i_valid` : Input pixel valid
- `i_gray`  : 8-bit grayscale pixel
- `i_end`   : End-of-frame indicator

### Output
- `o_valid`   : Output pixel valid
- `o_gray_eq` : Equalized grayscale pixel
- `o_done`    : Frame processing complete

Back-pressure is handled using a valid/ready handshake.

---

## Verification Methodology

- A **self-checking SystemVerilog testbench** is used
- RTL output is compared pixel-by-pixel against a **C reference model**
- Random back-pressure is applied to validate handshake robustness
- Simulation terminates immediately on mismatch

---

## Performance Summary

- Image size: 320 × 240
- Throughput: 1 pixel / cycle
- Latency: Histogram + CDF + streaming remap
- Target clock period: 7.5 ns
- Estimated area: ~0.20 mm² (32 nm standard-cell library)

---

## Applications
- FPGA-based image preprocessing
- Edge AI vision pipelines
- Hardware–software co-design research

---

## Author
Taewoo Kang  
B.S. Electronic Engineering, HUFS  
Research Interests: VLSI Design, FPGA, Hardware-Oriented Algorithms
