# sTPU
Simplified Google TPU RTL with systolic array and memory controller for convolution.

The following figure represents the design of a systolic array.

![Screenshot from 2023-05-20 14-01-31](https://github.com/Sequner/sTPU/assets/47627472/db972131-1947-48d0-af3e-55422057f5cc)

Mac.sv has the RTL of a single MAC unit.

MacArray.sv creates an array of MAC units that comprises the systolic array.

MemoryController.sv controls the data flow of weights, input feature maps, and output feature maps to perform GEMM (General Matrix Multiply)-based convolution operation.

Systolic.sv is a wrapper for the systolic array.

Current design only allows convolution of 16x16 images by 3x3 weights.
