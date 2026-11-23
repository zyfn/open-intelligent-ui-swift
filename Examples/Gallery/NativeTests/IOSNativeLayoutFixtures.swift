/// The same programs are compiled into the SDK unit tests and the Gallery's
/// debug-only UI-test host. This is fixture data, not a component implementation.
enum IOSNativeLayoutFixtures {
    static let compositeCards = """
        root=CompositeCardBlock([a,b],"grid",true)
        a=CompositeCardItem("a",ImageTextLarge("","First photo","A quiet room by the lake"),[Text("text","A complete explanation remains visible.")],{price:BoldText("number","¥12,345"),button:Button("Book first room",@OpenUrl("https://example.invalid/a"))})
        b=CompositeCardItem("b",ImageTextLarge("","Second photo","Another room close to the station"),[Text("text","The second offer keeps its own action.")],{price:BoldText("number","¥9,876"),button:Button("Book second room",@OpenUrl("https://example.invalid/b"))})
        """

    static let wrappingDetail = "The full explanation wraps inside the card without taking space from its neighbour."
    static var wrappingCards: String {
        let cards = ["a", "b", "c"].map {
            "Card([Image(\"\($0)\"),CardHeader(\"Complete title \($0)\"),TextContent(\"\(wrappingDetail)\")],\"clear\",\"column\",\"xs\")"
        }
        return "root=Stack([\(cards.joined(separator: ","))],\"row\",\"m\",\"start\",\"start\",true)"
    }

    static let buttons = """
        $direction="column"
        root=Stack([TextContent($direction),Buttons([a,b,c],$direction)])
        a=Button("One")
        b=Button("Two")
        c=Button("A substantially longer third action")
        """

    static let stackAlignment = """
        $alignment="stretch"
        root=Stack([TextContent($alignment),Stack([Button("One")],"column","m",$alignment)])
        """

    static let optionDescription = String(repeating: "A complete recommendation with a useful reason. ", count: 4)
    static var options: String {
        "root=OptionCards(\"choice\",\"single\",[OptionCard(\"a\",\"First\",\"\(optionDescription)\",Icon(\"train\")),OptionCard(\"b\",\"Second\",null,Icon(\"bus\")),OptionCard(\"c\",\"Third\",null,Icon(\"car\"))])"
    }

    static let pager = """
        root=Carousel([[CardHeader("First carousel page"),TextContent("The first card remains part of the same reading track.")],[CardHeader("Second carousel page"),TextContent("The second card is reached by a real horizontal drag.")],[CardHeader("Third carousel page"),TextContent("The third card completes the same reading track.")]],"card")
        """

    static let streamingPrefix = "root=VisualCardBlock([a,b],\"carousel\",true)\na=VisualCardItem(BoldText(\"text\",\"First\"),\"f"
    static let streamingSuffix = "irst\",null)\nb=VisualCardItem(BoldText(\"text\",\"Second\"),\"second\",null)"
}
