import Raylib
import TSOFiles

extension RasterImage {
    /// A texture of it, with smooth scaling, or `nil` if raylib can't make one. Call after the
    /// window opens; the caller unloads it before the window closes.
    func makeTexture() -> Texture2D? {
        var pixels = rgba
        guard width > 0, height > 0, pixels.count == width * height * 4 else { return nil }
        let texture = pixels.withUnsafeMutableBytes { bytes in
            LoadTextureFromImage(Image(data: bytes.baseAddress, width: Int32(clamping: width), height: Int32(clamping: height),
                                       mipmaps: 1, format: Int32(truncatingIfNeeded: PixelFormat.uncompressedR8g8b8a8.rawValue)))
        }
        guard IsTextureValid(texture) else { return nil }
        SetTextureFilter(texture, .bilinear)
        return texture
    }
}
