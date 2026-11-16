// General OpenUI composition guidance. Component schemas and action contracts
// continue to come from the pinned catalog; these rules describe presentation.
export const groupNotes = {
  Layout: [
    '- Organize a reply by its information relationships. Use Stack for continuous reading and sections; use Tabs for alternative views and Accordion for optional detail.',
    '- In column Stacks, use gap="s" between a heading and its content, gap="m" between related paragraphs, and gap="xl" between sections. Explicit layout arguments remain authoritative.',
    '- For side-by-side content use Stack with direction="row" and wrap=true. Prefer justify="start" to avoid large gutters; readable content may reflow to fewer columns.',
    '- Modal("Title", $visible, [content]) uses a boolean binding. A form inside it still owns its own submit buttons.',
  ],
  Content: [
    '- Use TextContent Markdown headings for page/section hierarchy, InlineHeader for object names, and ordinary TextContent for the main explanation. Large or heavy body variants are emphasis, not substitutes for headings.',
    '- Card groups an independent object or bounded task. Ordinary sections and explanations can remain directly in a Stack.',
    '- TextCallout is a persistent aside or constraint. Callout with a writable visible binding can show transient feedback; unbound Callout remains visible. Use neutral/info for quiet notes and explicit status variants for real status.',
    '- Image and ImageBlock preserve the complete image in a stable media slot. ImageTextLarge is a cover/banner; ImageText is a thumbnail. Choose the component by purpose, using real provided image URLs.',
    '- ImageGallery previews related images. Supply details only when there is meaningful accompanying information; keep long explanations in normal reading content.',
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
    '- Use one clear primary submit for a task, with secondary actions only when they serve a distinct purpose. Form itself is a transparent field group; add Card only for a meaningful panel boundary.',
  ],
  Cards: [
    '- Use card collections for independent, comparable objects with consistent anatomy. Do not invent more objects to fill a grid or use a card for every paragraph.',
    '- SnippetCardItem presents a compact key/value fact; OverviewCardItem presents a compact object with an optional metric. Core explanations belong in body text, not in a small subtitle.',
    '- CompositeCardItem accepts its declared header, body and footer slots. Use object naming in the header, new supporting information in the body, and price/action in the footer; avoid repeating the same phrase in every slot.',
    '- VisualCardItem and background-image ContextCardItem suit short copy over photographs. Long explanations belong below or outside the photo, preserving the photograph itself.',
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
    'Use Card for an independent object or bounded task. Charts, forms, follow-ups and ordinary sections do not automatically need a Card.',
    'Use TextCallout for a distinct aside, limitation or warning. Do not wrap normal explanations in callouts or invent generic titles such as Information or Note.',
    'Choose Image/ImageBlock for a complete content image, ImageTextLarge for a photographic cover/banner, and ImageText for a thumbnail. Do not infer image purpose from a URL or force a product outline or diagram into a cover.',
    'Use real images supplied by the user or tools. Do not invent image URLs, placeholder objects, prices, availability or factual data. Label explicitly requested hypothetical examples as hypothetical.',
    'Keep photo-overlay copy short; put longer explanations in reading content. Gallery details must add useful information instead of repeating the surrounding text.',
    'For SVG diagrams, use a tight meaningful viewBox, short labels readable at phone width, and colors with clear meaning. Keep long explanations in adjacent text. Do not embed an extra preview button or instructions.',
    'Choose a chart to explain a quantitative relationship and a table to support exact comparison. Avoid repeated metrics, charts and lists that add no information.',
    'Within one decision area, emphasize its main next action and use secondary treatment for alternatives and references. Preserve the actual action, destination and payload.',
    'Use FollowUpBlock at the end of the response for useful next questions. It can be a direct child of Stack and does not require a Card wrapper.',
    'For forms, define one FormControl reference per field and pass Buttons(...) as the second Form argument: Form(name, buttons, fields). Never nest Form inside Form.',
    'Declare single/multiple selection through the actual field mode. Do not generate Required/Multi-select badges, duplicate field labels, validation errors or resource-retry controls.',
    'Reset fields only when the task calls for it; use @Reset($var1, $var2) to restore defaults. Reactive variables update their dependent expressions and Queries.',
    'Keep existing action semantics: a multi-query refresh can use Action([@Run(mutation), @Run(query1), @Run(query2)]). Use existing Tabs, Accordion and Modal before inventing equivalent visibility logic.',
    'Always pass a category to Icon for its supported fallback. Use EditableTable only when editing is requested; the consuming app owns persistence.',
    'Use Map for meaningful coordinate relationships. Initial overview and selected-place details are component behavior; do not duplicate map controls or details outside it.',
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
