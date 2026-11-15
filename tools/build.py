from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "dist" / "MergeAdvisor.lua"

MODULES = [
    ("GameConfigLoader", "src/core/GameConfigLoader.lua"),
    ("InventoryReader", "src/core/InventoryReader.lua"),
    ("IncomeCalculator", "src/calculators/IncomeCalculator.lua"),
    ("MainWindow", "src/ui/MainWindow.lua"),
    ("Bootstrap", "src/core/Bootstrap.lua"),
]

def read_module(relative_path):
    path = ROOT / relative_path

    if not path.is_file():
        raise FileNotFoundError(
            f"File belum ditemukan: {relative_path}"
        )

    source = path.read_text(encoding="utf-8").strip()

    if not source:
        raise ValueError(f"File kosong: {relative_path}")

    return source

def build():
    output = [
        "-- MERGE ADVISOR",
        "-- Generated automatically by tools/build.py",
        "-- Do not edit this generated file directly.",
        "",
    ]

    for module_name, relative_path in MODULES:
        source = read_module(relative_path)

        output.extend([
            f"-- MODULE: {relative_path}",
            f"local {module_name} = (function()",
            source,
            "end)()",
            "",
        ])

        print(f"[OK] {relative_path}")

    output.extend([
        "-- START APPLICATION",
        "local controller = Bootstrap.Start({",
        "    Modules = {",
        "        GameConfigLoader = GameConfigLoader,",
        "        InventoryReader = InventoryReader,",
        "        IncomeCalculator = IncomeCalculator,",
        "        MainWindow = MainWindow,",
        "    }",
        "})",
        "",
        "return controller",
    ])

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(output) + "\n", encoding="utf-8")

    print("")
    print("[SUCCESS] Bundler selesai.")
    print(f"Output: {OUTPUT.relative_to(ROOT)}")
    print(f"Ukuran: {OUTPUT.stat().st_size:,} bytes")

if __name__ == "__main__":
    try:
        build()
    except Exception as error:
        print(f"[BUILD ERROR] {error}")
        sys.exit(1)
