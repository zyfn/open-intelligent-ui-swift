// General OpenUI composition guidance. Component schemas and action contracts
// continue to come from the pinned catalog; these rules describe presentation.
export const groupNotes = {
  Layout: [
    '- Organize a reply by its information relationships. Use Stack for continuous reading and sections; use Tabs for alternative views and Accordion for optional detail.',
    '- In column Stacks, use gap="s" between a heading and its content, gap="m" between related paragraphs, and gap="xl" between sections. Explicit layout arguments remain authoritative.',
    '- For grid-like collections use Stack with direction="row", wrap=true and justify="start". This is a collection layout, not a rule for every pair of adjacent values or actions.',
    '- Modal("Title", $visible, [content]) uses a boolean binding. A form inside it still owns its own submit buttons.',
  ],
  Content: [
    '- Use TextContent Markdown headings for page/section hierarchy, InlineHeader for object names, and ordinary TextContent for the main explanation. Large or heavy body variants are emphasis, not substitutes for headings.',
    '- Use Stack for the response, sections, explanations and sequences. Use Card only when one concrete object needs a comparison, selection or action boundary; a heading or a list of attributes alone does not justify a card.',
    '- TextCallout is a persistent aside or constraint. Callout with a writable visible binding can show transient feedback; unbound Callout remains visible. Use neutral/info for quiet notes and explicit status variants for real status.',
    '- Image and ImageBlock fill the configured cover aspect ratio; their viewer provides complete-image inspection. ImageTextLarge is a cover/banner; ImageText is a thumbnail. Use real provided image URLs and keep essential explanations in text.',
    '- ImageGallery previews related images and owns access to the full collection. Supply details only when useful; do not add a separate count, view-all button or surrounding Card.',
  ],
  'Charts (2D)': [
    '- Charts accept aligned label and numeric series arrays: LineChart(labels, [Series("Name", values)]). Derive both arrays from the same ordered data.',
    '- Put a useful conclusion and section heading near a chart. A chart does not require an extra Card wrapper.',
    '- Add a Table or a second chart only when it provides information the first view does not. Detailed values remain available through native chart inspection.',
    '- Use Tabs when the user benefits from alternative views of the same data.',
  ],
  Forms: [
    '- Form(name, buttons, fields) takes Buttons(...) as its second argument. Define each FormControl separately for progressive field streaming; never nest Form inside Form.',
    '- FormControl owns the field label. Avoid repeating that label as a separate heading immediately above the same field.',
    '- OptionCards and Chips declare single/multiple selection through their mode. The controls convey selection state; do not add a separate selection-mode badge.',
    '- Keep meaningful labels and hints. Supply validation rules such as required, email, min, max, minLength, maxLength, pattern, url, numeric; the renderer owns validation errors.',
    '- Form already presents one task card containing its fields and actions. Place Form directly in the surrounding Stack; do not wrap it or each FormControl in another Card. Use one clear primary submit and only useful secondary actions.',
  ],
  Cards: [
    '- Use card collections only when users need to compare or act on separate objects. The collection items already own their surfaces; do not wrap the whole collection in another Card or invent objects to fill a grid.',
    '- SnippetCardItem and OverviewCardItem support facts that benefit from scanning or comparison. Do not automatically turn an introduction or every number into overview cards; explain continuous reasoning in TextContent.',
    '- CompositeCardItem accepts its declared header, body and footer slots. Use object naming in the header, new supporting information in the body, and price/action in the footer; avoid repeating the same phrase in every slot.',
    '- VisualCardItem and background-image ContextCardItem use a photograph as the card background, with their tag/title and body over the image. Keep overlay copy concise; put extended explanations in adjacent reading content.',
    '- Text, BoldText, IconText, ImageText, ImageTextLarge and MetricIndicator components are object building blocks. Follow the declared slot schemas and prefer TextContent for a continuous explanation.',
  ],
};

export const promptOptions = {
  additionalRules: [
    'Start with the content most useful for the current user intent. Organize by meaning before selecting components; do not force every reply into the same card or dashboard template.',
    'Use only the registered component names, positional arguments and allowed slots. Explicit user requests for layout or style take priority over these defaults.',
    'Use ordinary TextContent/Markdown for core explanations. Small, secondary subtitles are for metadata or supplementary context, not the main reasoning.',
    'Use consistent heading levels for peer sections and smaller object headings within them. Do not add duplicate titles or increase body size merely to create hierarchy.',
    'Use column Stack gap="s" for a heading with its content, "m" for related paragraphs and "xl" between sections. Nested grouping expresses these relationships without an extra surface.',
    'Default to a continuous Stack of headings, text and relevant media. Reserve Card for a concrete object being compared, selected or acted on; do not cardify the response, ordinary sections, paragraphs, charts, tables or follow-ups.',
    'Use TextCallout for a distinct aside, limitation or warning. Do not wrap normal explanations in callouts or invent generic titles such as Information or Note.',
    'Image/ImageBlock and ImageTextLarge use cover framing; ImageText is a thumbnail, and SVG expresses diagrams. The media viewer provides complete-image inspection. Do not infer image purpose from its URL or put essential instructions only inside a cropped image.',
    'Use real images supplied by the user or tools. Do not invent image URLs, placeholder objects, prices, availability or factual data. Label explicitly requested hypothetical examples as hypothetical.',
    'Keep photo-overlay copy short; put longer explanations in reading content. Gallery details must add useful information instead of repeating the surrounding text.',
    'For SVG diagrams, use a tight meaningful viewBox, short labels readable at phone width, and colors with clear meaning. Keep long explanations in adjacent text. Do not embed an extra preview button or instructions.',
    'Choose a chart to explain a quantitative relationship and a table to support exact comparison. Avoid repeated metrics, charts and lists that add no information.',
    'Within one decision area, emphasize its main next action and use secondary treatment for alternatives and references. Preserve the actual action, destination and payload.',
    'Use FollowUpBlock at the end of the response for useful next questions. It can be a direct child of Stack and does not require a Card wrapper.',
    'A complete Form is one task card by default. Place it directly in Stack without an extra Card, define one FormControl per field, and pass Buttons(...) as its second argument: Form(name, buttons, fields). Never nest Form inside Form.',
    'Declare single/multiple selection through the actual field mode. Do not generate Required/Multi-select badges, duplicate field labels, validation errors or resource-retry controls.',
    'Reset fields only when the task calls for it; use @Reset($var1, $var2) to restore defaults. Reactive variables update their dependent expressions and Queries.',
    'Keep existing action semantics: a multi-query refresh can use Action([@Run(mutation), @Run(query1), @Run(query2)]). Use existing Tabs, Accordion and Modal before inventing equivalent visibility logic.',
    'Always pass a category to Icon for its supported fallback. Use EditableTable only when editing is requested; the consuming app owns persistence.',
    'Use Map for meaningful coordinate relationships. The component owns point selection, the selected-place card and external-place links; do not duplicate these controls or details outside it.',
  ],
  examples: [
    `root = Stack([summary, explanation, note, followUps], "column", "xl")
summary = TextContent("The main result is **unchanged**. The useful difference is how the work is distributed.")
explanation = Stack([heading, body], "column", "s")
heading = TextContent("## How to read the result")
body = TextContent("Start with the total, then compare the parts.\\n\\nA larger part explains more of the total; it does not by itself explain the cause.")
note = TextCallout("neutral", null, "The sample covers completed work only.")
followUps = FollowUpBlock([FollowUpItem("Compare the parts"), FollowUpItem("Explain the assumptions")])`,
    `root = Stack([summary, comparison], "column", "xl")
summary = TextContent("In this hypothetical example, **A is faster and B needs less storage**.")
comparison = Stack([heading, table], "column", "s")
heading = TextContent("## Compare the trade-offs")
table = Table([Col("Option", names), Col("Time (s)", times, "number"), Col("Storage (MB)", storage, "number")])
names = ["A", "B"]
times = [4, 7]
storage = [80, 35]`,
    `root = Stack([summary, section], "column", "xl")
summary = TextContent("In this hypothetical example, completed work increases across the three months.")
section = Stack([heading, chart], "column", "s")
heading = TextContent("## Completed work")
chart = BarChart(months, [Series("Completed", counts)], "grouped")
months = ["January", "February", "March"]
counts = [12, 18, 24]`,
    `root = Stack([heading, form], "column", "s")
heading = TextContent("## Contact details")
form = Form("contact", actions, [nameField, emailField, messageField])
nameField = FormControl("Name", Input("name", "Your name", "text", { required: true }))
emailField = FormControl("Email", Input("email", "you@example.com", "email", { required: true, email: true }))
messageField = FormControl("Message", TextArea("message", "What would you like to discuss?", 4))
actions = Buttons([Button("Continue", @ToAssistant("Use these contact details"), "primary")])`,
    `root = Stack([heading, form], "column", "s")
heading = TextContent("## Choose your preferences")
form = Form("preferences", actions, [paceField, featuresField])
paceField = FormControl("Pace", OptionCards("pace", "single", [relaxed, active], { required: true }))
relaxed = OptionCard("relaxed", "Relaxed", "More time at each stop")
active = OptionCard("active", "Active", "More variety during the day")
featuresField = FormControl("Features", Chips("features", "multiple", [ChipItem("quiet", "Quiet"), ChipItem("outdoors", "Outdoors")]))
actions = Buttons([Button("Use these preferences", @ToAssistant("Use my selected preferences"), "primary")])`,
    `root = Stack([summary, offers], "column", "xl")
summary = TextContent("These hypothetical offers illustrate a primary choice and an alternative.")
offers = CompositeCardBlock([standard, compact])
standard = CompositeCardItem("standard", standardTitle, [standardDetail], { price: BoldText("text", "$29"), button: standardAction })
standardTitle = IconText(Icon("package", "shopping"), "neutral", "m", "Standard", "", true, "horizontal")
standardDetail = Text("text", "More capacity for regular use")
standardAction = Button("Choose standard", @ToAssistant("Choose the standard option"), "primary")
compact = CompositeCardItem("compact", compactTitle, [compactDetail], { price: BoldText("text", "$19"), button: compactAction })
compactTitle = IconText(Icon("box", "shopping"), "neutral", "m", "Compact", "", true, "horizontal")
compactDetail = Text("text", "Smaller size for occasional use")
compactAction = Button("Choose compact", @ToAssistant("Choose the compact option"), "secondary")`,
  ],
};
