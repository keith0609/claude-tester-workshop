#!/usr/bin/env python3
"""md-to-gherkin-with-model-choice.py

Converteer markdown testcases naar Gherkin .feature via de Anthropic API.
Demonstreert model-keuze per pipeline-stap.

Usage:
  python md-to-gherkin-with-model-choice.py in.md out.feature --model haiku
  python md-to-gherkin-with-model-choice.py in.md out.feature --model sonnet
"""
import os
import sys
import argparse
import time
from pathlib import Path

try:
    from anthropic import Anthropic
except ImportError:
    print("Error: anthropic package niet gevonden. Installeer met:")
    print("  pip install --user anthropic")
    sys.exit(1)

# Model-IDs via env-var (aanbevolen) of kortere aliases als default.
# Korte aliases zijn stabieler dan gepinde datumversies.
# Verifieer actuele IDs op docs.claude.com.
MODELS = {
    "haiku":  os.environ.get("ANTHROPIC_HAIKU_MODEL",  "claude-haiku-4-5"),
    "sonnet": os.environ.get("ANTHROPIC_SONNET_MODEL", "claude-sonnet-4-5"),
}

# Prompt gebruikt <<<MARKDOWN>>> markers in plaats van embedded backticks,
# zodat copy/paste-problemen in markdown-bronnen worden vermeden.
PROMPT = """Je bent een senior tester. Converteer de input tussen de markers
naar geldig Gherkin .feature format.

<<<MARKDOWN>>>
{markdown}
<<<END_MARKDOWN>>>

Output: alleen geldige Gherkin, geen uitleg.
Regels:
- Feature: afgeleid uit de input-context
- Per testcase één Scenario
- Given / When / Then volledige zinnen
- Geen placeholder-tekst
"""


def convert(markdown_text: str, model_key: str) -> str:
    """Converteer markdown naar Gherkin via Claude API."""
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Error: ANTHROPIC_API_KEY env var niet gezet.")
        print("  Windows: [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY','YOUR_ANTHROPIC_API_KEY_HERE','User')")
        print("  macOS/Linux: export ANTHROPIC_API_KEY='YOUR_ANTHROPIC_API_KEY_HERE'")
        sys.exit(1)

    client = Anthropic()
    model = MODELS[model_key]
    response = client.messages.create(
        model=model,
        max_tokens=2000,
        messages=[{"role": "user", "content": PROMPT.format(markdown=markdown_text)}],
    )
    return response.content[0].text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="markdown inputbestand")
    parser.add_argument("output", help="gherkin .feature outputbestand")
    parser.add_argument(
        "--model",
        choices=["haiku", "sonnet"],
        default="haiku",
        help="model-keuze (default: haiku)",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input-bestand niet gevonden: {args.input}")
        sys.exit(1)

    md_text = input_path.read_text(encoding="utf-8")

    t0 = time.time()
    feature = convert(md_text, args.model)
    elapsed = time.time() - t0

    Path(args.output).write_text(feature, encoding="utf-8")

    print(f"Model:    {args.model} ({MODELS[args.model]})")
    print(f"Tijd:     {elapsed:.1f}s")
    print(f"Output:   {args.output}")


if __name__ == "__main__":
    main()
