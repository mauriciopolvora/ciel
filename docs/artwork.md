# Ciel artwork

`Resources/CloudPainting.png` is the original generated painting. It was created with the built-in image generation tool on 29 September 2026. It is inspired by Claude Monet's impressionist brushwork. It is not a reproduction or scan of a specific Monet painting.

The painting is included with the project under its MIT license. `scripts/GenerateIcon.swift` scales it, clips it to a macOS icon silhouette, and adds a subtle edge and shadow. It creates all standard icon sizes. `iconutil` assembles the `.icns` file. Keep the painting source so builds do not depend on an external generation service.

## Generation prompt

> Use case: stylized-concept. Asset type: original square painting for the Ciel native macOS app icon. Primary request: a beautiful cloud painting inspired by Claude Monet's impressionist brushwork. A single luminous, large ivory cumulus cloud against a gentle blue sky, soft lavender shadows and a little warm peach sunlight. Hand-painted oil texture, broken color, expressive visible brushstrokes, quiet and airy. Composition: simple and bold enough to read as a small app icon, cloud occupies central two thirds, sky fills the entire square edge to edge. Flat painting only, no device mockup, no frame, no rounded corners, no lettering, no symbols, no watermark. Render a square high-quality image.
