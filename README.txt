Hermes + Gondolin Secret Protection (macOS Apple Silicon)

Architecture
  macOS (Apple Silicon)
    → Colima VM (Linux, VZ framework)
      → Docker container (hermes-gondolin image, Gondolin "host")
        → Gondolin micro-VM (QEMU/TCG software emulation)
          → Hermes runs here, sees only GONDOLIN_SECRET_<random> placeholders
        ← Gondolin HTTP proxy substitutes real keys for allowed API hosts only

How it works
- Secrets from provider.env are never exported into the environment
- Gondolin replaces each API key with a random placeholder token
- Hermes (inside the micro-VM) only ever sees placeholder values
- The Gondolin proxy on the host side intercepts outbound HTTP requests
  and substitutes real keys, but ONLY for allowed destination hosts:
    OPENAI_API_KEY     → api.openai.com (+ custom OPENAI_BASE_URL host)
    ANTHROPIC_API_KEY  → api.anthropic.com
    OPENROUTER_API_KEY → openrouter.ai
- Attempts to send keys to unauthorized hosts are blocked

Prerequisites
  brew install colima docker

Quick start
  1) Add your API key(s) to secrets/provider.env
     chmod 600 secrets/provider.env

  2) make up

  3) Check status in another terminal:
     make status

  4) Stop when done:
     make down

Notes
- `make up` starts Colima, builds the image (Node.js + QEMU + Gondolin + Hermes),
  and launches the Hermes TUI inside a Gondolin-protected micro-VM.
