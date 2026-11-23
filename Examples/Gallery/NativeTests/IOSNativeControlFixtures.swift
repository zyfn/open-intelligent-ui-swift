/// Shared source programs for in-process UIKit checks and the Gallery UI tests.
/// This file is compiled into both test consumers; the SDK does not depend on it.
enum IOSNativeControlFixtures {
    static let input = #"root=Input("draft",null,"text",null,"initial value")"#
    static let ambientInput = #"root=Input("draft",null,"text",null,"ambient value")"#
    static let textArea = #"root=TextArea("notes","Write notes",3,null,"Initial notes")"#

    private static let switches = #"SwitchGroup("settings",[SwitchItem("Reminders","","reminders",false)])"#
    private static let select = #"Select("route",[SelectItem("walk","Walk"),SelectItem("bike","Bike")],"Choose route")"#
    private static let radio = #"RadioGroup("pace",[RadioItem("Easy","","easy"),RadioItem("Full","","full")],"easy")"#
    private static let checkbox = #"CheckBoxGroup("preferences",[CheckBoxItem("Quiet","","quiet",false)])"#

    static let switchAndSelect = "root=Stack([\(switches),\(select)])"
    static let selection = "root=Stack([\(radio),\(checkbox),\(switches),\(select)])"
    static let form = #"root=Form("contact",Buttons([Button("Send",@ToAssistant("Contact details"))]),[FormControl("Email",Input("email","Email address","email",{required:true,email:true}))])"#
    private static let sliderComponent = #"Slider("amount","continuous",0,100,1,[10],"Budget")"#
    static let sliderInput = "root=\(sliderComponent)"
    static let slider = "root=Form(\"quote\",Buttons([Button(\"Send amount\",@ToAssistant(\"Amount details\"))]),[FormControl(\"Budget\",\(sliderComponent))])"

    static func modal(size: String) -> String {
        """
        $open=false
        $sheetStatus="Awaiting native sheet"
        root=Stack([TextContent("Underlying page"),Button("Open details",@Set($open,true)),Modal("Details",$open,[TextContent("Inside the modal"),TextContent($sheetStatus)],"\(size)")])
        """
    }
}
