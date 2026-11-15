
/// Action construction shared by native component libraries; presentation belongs to each library.
public enum OpenUIActions {
    public static func openURL(_ url: String) -> ActionPlan { ActionPlan(steps: [.openUrl(urlAST: .str(url))]) }
    public static func continueConversation(_ message: String, context: ASTNode? = nil) -> ActionPlan {
        ActionPlan(steps: [.continueConversation(messageAST: .str(message), contextAST: context)])
    }
}
