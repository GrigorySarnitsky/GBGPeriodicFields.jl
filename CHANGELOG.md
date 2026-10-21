# Changelog

## 0.1.1 — 2026-10-21

The install instructions in the README and on the documentation's home page now add the fleet's
registry, GBGRegistry, beside `General` and install the package by name, which gives its latest
release; 0.1.0's installed it by URL, which gives the newest commit. The test and documentation
environments now name the package's own path, so a fresh clone instantiates them, and the test
environment resolves on Julia 1.13. The package's code is unchanged from 0.1.0.

## 0.1.0 — 2026-10-21

The first release. GBGPeriodicFields provides real scalar, vector and second-order tensor fields on
three-dimensional periodic boxes, in physical and real-to-complex spectral representation, on the CPU
with multithreading and on one GPU through CUDA or ROCm. It covers the fiberwise algebra, the
differential operators applied as spectral multipliers, periodic convolution with four kernel storage
classes, the L² and measure reductions including radial spectra and correlations, point sets with
their own algebra, interpolation and its adjoint anterpolation by local splines or exact spectral
transfer, and HDF5 persistence of fields, point values and transfer schemes. In-place operations
allocate nothing, which the test suite asserts.
