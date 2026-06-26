import Testing

@main struct SilenciTestDriver {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
