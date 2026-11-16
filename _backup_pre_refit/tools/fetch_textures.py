"""Downloads the CC0 PBR textures used by the school from Poly Haven.

    python tools/fetch_textures.py

Saves textures/polyhaven/<asset>/<asset>_{diff,nor_gl,rough}_1k.jpg and
textures/polyhaven/index.json (real-world size of each texture in metres,
used by tools/build_school.gd to scale tiles correctly).
All Poly Haven assets are CC0 (public domain): https://polyhaven.com/license
"""
import json
import os
import sys
import urllib.request

ASSETS = [
    "interior_tiles", "floor_tiles_06", "laminate_floor_02",
    "rounded_square_tiled_wall", "long_white_tiles", "anti_skid_tiles",
    "rubber_tiles", "painted_plaster_wall", "white_stucco", "grey_plaster",
    "plywood", "lacquered_cherry_wood", "concrete_pavement", "asphalt_02",
    "grass_ground",
]
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough"}
RES = "1k"
UA = {"User-Agent": "godot-school-texture-fetch"}
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "textures", "polyhaven")


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def main():
    os.makedirs(ROOT, exist_ok=True)
    index = {}
    for asset in ASSETS:
        info = get_json(f"https://api.polyhaven.com/info/{asset}")
        files = get_json(f"https://api.polyhaven.com/files/{asset}")
        dims = info.get("dimensions", [2000, 2000])  # millimetres
        out_dir = os.path.join(ROOT, asset)
        os.makedirs(out_dir, exist_ok=True)
        entry = {"size_m": [dims[0] / 1000.0, dims[1] / 1000.0], "maps": {}}
        for key, short in MAPS.items():
            url = files[key][RES]["jpg"]["url"]
            name = f"{asset}_{short}_{RES}.jpg"
            dest = os.path.join(out_dir, name)
            if not os.path.exists(dest):
                with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r, open(dest, "wb") as f:
                    f.write(r.read())
            entry["maps"][short] = f"res://textures/polyhaven/{asset}/{name}"
        index[asset] = entry
        print(f"{asset:28s} {entry['size_m'][0]:.2f} x {entry['size_m'][1]:.2f} m")
    with open(os.path.join(ROOT, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1)
    with open(os.path.join(ROOT, "LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write("Textures from Poly Haven (https://polyhaven.com), licensed CC0 1.0 (public domain).\n"
                "No attribution required. Assets: " + ", ".join(ASSETS) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
