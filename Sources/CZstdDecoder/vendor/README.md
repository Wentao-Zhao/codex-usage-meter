# Zstandard decoder

Official Zstandard v1.5.7, decoder-only amalgamation generated without modifications to upstream code.

Source: https://github.com/facebook/zstd/tree/v1.5.7

Archive: https://codeload.github.com/facebook/zstd/tar.gz/refs/tags/v1.5.7

Archive SHA-256: `37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3`.

Generation (run from the upstream `build/single_file_libs` directory):

```sh
python3 combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.inc zstddeclib-in.c
```

The BSD license in `LICENSE` is selected. It is also copied into the packaged app's resources. The surrounding `CMZstd.c` bridge limits streaming window memory to 8 MiB; no compressor, external process or network access is used at runtime.

Bundled xxHash code: Copyright (c) Yann Collet - Meta Platforms, Inc. It is covered by the same upstream BSD license. All upstream copyright notices remain in the generated source.
