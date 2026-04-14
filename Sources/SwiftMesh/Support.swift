extension Optional {
    func orFatalError(_ message: @autoclosure () -> String = String(), file: StaticString = #file, line: UInt = #line) -> Wrapped {
        guard let value = self else {
            fatalError(message(), file: file, line: line)
        }
        return value
    }
}
