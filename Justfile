# Justfile for generating test fixtures

fixtures_dir := "Tests/GoldenImageTests/Fixtures"

# Generate all test fixtures
generate-all: generate-sizes generate-baseline generate-subtle generate-broad generate-alpha generate-colorspace generate-edge generate-content

# Clean fixtures
clean:
    rm -rf {{fixtures_dir}}

# Generate size variations
generate-sizes:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image
    import os

    fixtures_dir = "{{fixtures_dir}}"

    sizes = [
        (1, 1, "tiny_1x1"),
        (8, 8, "small_8x8"),
        (256, 256, "medium_256x256"),
        (2048, 2048, "large_2048x2048"),
        (4096, 4096, "huge_4096x4096"),
        (8192, 8192, "ultra_8192x8192"),
    ]

    for width, height, name in sizes:
        img = Image.new("RGBA", (width, height))
        pixels = img.load()
        for y in range(height):
            val = int(255 * (y / height)) if height > 1 else 128
            for x in range(width):
                pixels[x, y] = (val, 0, 255 - val, 255)
        img.save(f"{fixtures_dir}/{name}.png")
        print(f"Generated {name}.png ({width}x{height})")

# Generate identical baseline pair
generate-baseline:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image

    fixtures_dir = "{{fixtures_dir}}"
    size = (512, 512)

    img = Image.new("RGBA", size)
    pixels = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            r = int(255 * (x / size[0]))
            b = int(255 * (y / size[1]))
            pixels[x, y] = (r, 128, b, 255)

    img.save(f"{fixtures_dir}/baseline_a.png")
    img.save(f"{fixtures_dir}/baseline_b.png")
    print("Generated baseline_a.png and baseline_b.png (identical pair)")

# Generate subtle difference images
generate-subtle:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image

    fixtures_dir = "{{fixtures_dir}}"
    size = (512, 512)

    base = Image.new("RGBA", size, (128, 128, 128, 255))
    base.save(f"{fixtures_dir}/subtle_base.png")
    print("Generated subtle_base.png")

    img_1px_small = Image.new("RGBA", size, (128, 128, 128, 255))
    pixels = img_1px_small.load()
    pixels[256, 256] = (129, 128, 128, 255)
    img_1px_small.save(f"{fixtures_dir}/subtle_1px_off.png")
    print("Generated subtle_1px_off.png (1 pixel changed by 1)")

    img_1px_large = Image.new("RGBA", size, (128, 128, 128, 255))
    pixels = img_1px_large.load()
    pixels[256, 256] = (0, 128, 128, 255)
    img_1px_large.save(f"{fixtures_dir}/subtle_1px_large.png")
    print("Generated subtle_1px_large.png (1 pixel changed by 128)")

    img_10px = Image.new("RGBA", size, (128, 128, 128, 255))
    pixels = img_10px.load()
    for i in range(10):
        pixels[256 + i, 256] = (129, 128, 128, 255)
    img_10px.save(f"{fixtures_dir}/subtle_10px_off.png")
    print("Generated subtle_10px_off.png (10 pixels changed by 1)")

# Generate broad difference images
generate-broad:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image

    fixtures_dir = "{{fixtures_dir}}"
    size = (512, 512)

    base = Image.new("RGBA", size, (255, 0, 0, 255))
    base.save(f"{fixtures_dir}/broad_base.png")
    print("Generated broad_base.png")

    img_half = Image.new("RGBA", size)
    pixels = img_half.load()
    for y in range(size[1]):
        for x in range(size[0]):
            if x < size[0] // 2:
                pixels[x, y] = (255, 0, 0, 255)
            else:
                pixels[x, y] = (0, 0, 255, 255)
    img_half.save(f"{fixtures_dir}/broad_half.png")
    print("Generated broad_half.png (50% different)")

    img_all = Image.new("RGBA", size, (0, 255, 0, 255))
    img_all.save(f"{fixtures_dir}/broad_all.png")
    print("Generated broad_all.png (completely different)")

# Generate alpha channel variations
generate-alpha:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image

    fixtures_dir = "{{fixtures_dir}}"
    size = (512, 512)

    alpha_opaque = Image.new("RGBA", size, (255, 0, 0, 255))
    alpha_opaque.save(f"{fixtures_dir}/alpha_opaque.png")
    print("Generated alpha_opaque.png")

    alpha_transparent = Image.new("RGBA", size, (255, 0, 0, 0))
    alpha_transparent.save(f"{fixtures_dir}/alpha_transparent.png")
    print("Generated alpha_transparent.png")

    alpha_50 = Image.new("RGBA", size, (255, 0, 0, 128))
    alpha_50.save(f"{fixtures_dir}/alpha_50.png")
    print("Generated alpha_50.png")

    alpha_gradient = Image.new("RGBA", size)
    pixels = alpha_gradient.load()
    for y in range(size[1]):
        alpha = int(255 * (y / size[1]))
        for x in range(size[0]):
            pixels[x, y] = (255, 0, 0, alpha)
    alpha_gradient.save(f"{fixtures_dir}/alpha_gradient.png")
    print("Generated alpha_gradient.png")

    alpha_pattern = Image.new("RGBA", size)
    pixels = alpha_pattern.load()
    square_size = 32
    for y in range(size[1]):
        for x in range(size[0]):
            if (x // square_size + y // square_size) % 2 == 0:
                pixels[x, y] = (255, 0, 0, 255)
            else:
                pixels[x, y] = (255, 0, 0, 0)
    alpha_pattern.save(f"{fixtures_dir}/alpha_pattern.png")
    print("Generated alpha_pattern.png")

# Generate color space test images
generate-colorspace:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image

    fixtures_dir = "{{fixtures_dir}}"
    size = (512, 512)

    srgb_red = Image.new("RGBA", size, (255, 0, 0, 255))
    srgb_red.save(f"{fixtures_dir}/srgb_red.png")
    print("Generated srgb_red.png")

    p3_red = Image.new("RGBA", size, (255, 0, 0, 255))
    p3_red.save(f"{fixtures_dir}/p3_red.png")
    print("Generated p3_red.png (note: actual P3 encoding requires proper color profile)")

    generic_red = Image.new("RGBA", size, (255, 0, 0, 255))
    generic_red.save(f"{fixtures_dir}/generic_red.png")
    print("Generated generic_red.png")

# Generate edge case images
generate-edge:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image

    fixtures_dir = "{{fixtures_dir}}"
    size = (512, 512)

    all_black = Image.new("RGBA", size, (0, 0, 0, 255))
    all_black.save(f"{fixtures_dir}/all_black.png")
    print("Generated all_black.png")

    all_white = Image.new("RGBA", size, (255, 255, 255, 255))
    all_white.save(f"{fixtures_dir}/all_white.png")
    print("Generated all_white.png")

    all_transparent = Image.new("RGBA", size, (0, 0, 0, 0))
    all_transparent.save(f"{fixtures_dir}/all_transparent.png")
    print("Generated all_transparent.png")

# Generate content variation images
generate-content:
    mkdir -p {{fixtures_dir}}
    #!/usr/bin/env -S uv run --with pillow python3
    from PIL import Image

    fixtures_dir = "{{fixtures_dir}}"
    size = (512, 512)

    gradient_smooth = Image.new("RGBA", size)
    pixels = gradient_smooth.load()
    for y in range(size[1]):
        for x in range(size[0]):
            r = int(255 * (x / size[0]))
            b = int(255 * (y / size[1]))
            pixels[x, y] = (r, 128, b, 255)
    gradient_smooth.save(f"{fixtures_dir}/gradient_smooth.png")
    print("Generated gradient_smooth.png")

    pattern_sharp = Image.new("RGBA", size)
    pixels = pattern_sharp.load()
    square_size = 32
    for y in range(size[1]):
        for x in range(size[0]):
            if (x // square_size + y // square_size) % 2 == 0:
                pixels[x, y] = (255, 255, 255, 255)
            else:
                pixels[x, y] = (0, 0, 0, 255)
    pattern_sharp.save(f"{fixtures_dir}/pattern_sharp.png")
    print("Generated pattern_sharp.png")

    photo_realistic = Image.new("RGBA", size)
    pixels = photo_realistic.load()
    for y in range(size[1]):
        for x in range(size[0]):
            r = (x * 7 + y * 13) % 256
            g = (x * 11 + y * 17) % 256
            b = (x * 13 + y * 19) % 256
            pixels[x, y] = (r, g, b, 255)
    photo_realistic.save(f"{fixtures_dir}/photo_realistic.png")
    print("Generated photo_realistic.png")
