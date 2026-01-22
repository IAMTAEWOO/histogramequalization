# Streaming Histogram Equalization Core (RTL)

This repository presents a fully streaming hardware implementation of
Histogram Equalization (HE) for grayscale images.

## Key Features
- Fully streaming architecture (no frame buffer)
- One-pixel-per-cycle throughput
- Valid/Ready handshake-based flow control
- Synthesizable Verilog RTL
- C reference model for bit-accurate verification

## Architecture Overview
- Histogram accumulation
- CDF computation
- LUT generation
- Streaming pixel remapping

## Directory Structure
...

## Simulation & Verification
- RTL vs C reference comparison
- ModelSim testbench provided

## Results
- Target clock: 133 MHz (7.5 ns)
- Area: ~0.20 mm² (32 nm standard-cell library)

## Applications
- FPGA-based image preprocessing
- Edge AI pipelines
