FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1
ENV HF_HOME=/root/.cache/huggingface
ENV TOKENIZERS_PARALLELISM=false

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    ca-certificates \
    ffmpeg \
    libsndfile1 \
    build-essential \
    pkg-config \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip setuptools wheel

RUN pip install --index-url https://download.pytorch.org/whl/cpu torch

RUN git clone --depth 1 https://github.com/microsoft/VibeVoice.git /app

WORKDIR /app

RUN git lfs install || true
RUN git lfs pull || true

RUN pip install -e ".[streamingtts]"

# Compatibility shim for the current VibeVoice voice-preset loader under
# PyTorch 2.6+. VibeVoice voice presets are loaded through torch.load(), and
# current upstream code is not yet compatible with PyTorch's safer default
# weights_only behavior.
#
# Scope: this creates sitecustomize.py inside this app-managed container only;
# it does not patch the user's macOS Python environment.
#
# Risk: this globally forces torch.load(..., weights_only=False) inside the
# image, which allows pickle-backed .pt loading. Do not reuse this image for
# arbitrary untrusted model files. Remove this shim once upstream VibeVoice
# supports safe voice-preset loading or pins a compatible loader directly.
RUN python - <<'PY'
import site
from pathlib import Path

site_dir = Path(site.getsitepackages()[0])
patch_file = site_dir / "sitecustomize.py"

patch_file.write_text(
'''
try:
    import torch
    _original_torch_load = torch.load

    def _vibevoice_torch_load_patch(*args, **kwargs):
        kwargs["weights_only"] = False
        return _original_torch_load(*args, **kwargs)

    torch.load = _vibevoice_torch_load_patch
except Exception:
    pass
'''
)

print(f"Created {patch_file}")
PY

RUN mkdir -p /app/outputs

CMD ["bash"]
