extension Primitives {
    /// Tests whether the caller is running an interaction on the stack object (opcode 37).
    ///
    /// True when the caller's running routine is an interaction's and the interaction at the head
    /// of its queue has the stack object as its callee; false otherwise, including with an empty
    /// queue.
    public enum TestSimInteractingWith: Primitive {
        public static let name = "test_sim_interacting_with"
        public static let opcode: UInt8 = 37

        public static func execute(_ operand: EmptyOperand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let caller = frame.caller else { throw .nullReference("Test Sim Interacting With has no caller") }
            let thread = caller.thread
            guard thread.stack.last?.isActionTree == true, let action = thread.queue.first else { return .gotoFalse }
            return action.callee === frame.stackObject ? .gotoTrue : .gotoFalse
        }
    }
}
