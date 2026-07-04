# Convolution

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Order   = [:module]
```

## Public API

### Convolution operations

```@docs
convolve!
convolve
⋆
```

### Kernel-multiplier builders

```@docs
spectral_cutoff
spectral_band
squared_wavenumber_field
assignment_window
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the
coefficientwise convolution kernel.

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Public  = false
Order   = [:function]
```
