import Foundation

/// Review candidate: layouts and ordinary controls only. Images deliberately
/// use their two required arguments; framing is owned by the renderer.
enum CompositionDemo {
    static let source = """
    root = Col([SegmentedControl($page,[{value:"preferences",label:"偏好设置"},{value:"journal",label:"城市手记"}],true),$page == "preferences" ? preferences : journal])
    $page = "preferences"
    $name = "我的阅读清单"
    $design = true
    $technology = true
    $culture = false
    $travel = true
    $depth = "balanced"
    $purpose = "discover"
    $minutes = 20
    $frequency = "daily"
    $notes = ""
    $saved = ""
    $view = "story"
    summary = ($design ? "产品设计 · " : "") + ($technology ? "科技 · " : "") + ($culture ? "文化 · " : "") + ($travel ? "旅行" : "")
    depthLabel = $depth == "brief" ? "简要" : $depth == "deep" ? "深入" : "均衡"
    purposeLabel = $purpose == "discover" ? "发现新知" : "聚焦主题"
    preferences = Col([
      Caption("为自己留一点阅读时间"),
      Title("你关心的，放在前面", "xl"),
      Text("选几个感兴趣的方向，让每天的阅读更合心意。", "sm", "muted"),
      Card([
        Title("关注什么", "md"),
        Input($name,"清单名称","text","给清单取个名字"),
        Grid([Checkbox($design,"产品设计"),Checkbox($technology,"科技"),Checkbox($culture,"文化"),Checkbox($travel,"旅行")],2,null,2)
      ]),
      Card([
        Title("怎样阅读", "md"),
        RadioGroup($purpose,[{value:"discover",label:"发现新知",description:"保持好奇，多看一些新的方向"},{value:"focus",label:"聚焦主题",description:"围绕当前关心的问题深入阅读"}],null,"list"),
        Label("内容深度"),
        SegmentedControl($depth,[{value:"brief",label:"简要"},{value:"balanced",label:"均衡"},{value:"deep",label:"深入"}],true),
        Slider($minutes,5,60,5,"每天留给阅读","分钟"),
        Select($frequency,[{value:"daily",label:"每天一点"},{value:"weekly",label:"每周集中阅读"}],"阅读节奏")
      ]),
      Disclosure("还有什么想告诉我们",[TextArea($notes,"补充偏好","例如，喜欢有出处的内容和清楚的解释",3)]),
      Card([
        Caption("你的阅读安排"),
        Title($name,"lg"),
        Text(summary,"sm"),
        Row([Text(purposeLabel + " · " + depthLabel,"sm","muted"),Spacer(),Text($minutes + " 分钟 / 天","sm","ink","medium",false,false,true)]),
        Caption($frequency == "daily" ? "每天一点" : "每周集中阅读"),
        $notes == "" ? null : Text($notes,"sm","muted")
      ],"soft"),
      Button("保存本页偏好",@Set($saved,$name + " · " + purposeLabel + " · " + depthLabel + " · " + $minutes + "分钟"),"solid","primary","md",null,false,true),
      $saved != "" ? Caption("本页已保存：" + $saved) : Caption("设置只保存在本页，用于体验排版与交互。")
    ])
    journal = Col([
      Caption("城市手记 · 杭州"),
      Title("把脚步放慢一点", "xl"),
      Text("从宫城的屋檐，到湖面的暮色。换一种看法，也换一种阅读节奏。","sm","muted"),
      SegmentedControl($view,[{value:"story",label:"读一篇"},{value:"collection",label:"看一组"},{value:"browse",label:"慢慢逛"}],true),
      $view == "story" ? story : $view == "collection" ? collection : browse,
      Text(["照片来自 Wikimedia Commons，仅作排版展示；来源与许可 ",Citation([{title:"德寿宫照片",url:"https://commons.wikimedia.org/wiki/File:Deshou_Palace.jpg"},{title:"西湖照片",url:"https://commons.wikimedia.org/wiki/File:West_Lake_(Hangzhou)_sunset_2016_January.jpg"}])],"xs","muted")
    ])
    story = Col([
      Image("\(ShowcasePrograms.westLake)","西湖日落"),
      Caption("日落时分，西湖的岸线与远山。"),
      Title("先看建筑，再看时间", "lg"),
      Text("建筑留下了一座城市的线索。沿着院落和屋檐慢慢走，细节往往比行程表更值得停留。"),
      Row([Image("\(ShowcasePrograms.deshou)","德寿宫建筑"),Col([Title("南宋宫城","md"),Badge("历史 · 建筑"),Text("从屋檐、庭院与遗址展示，观察城市曾经的样子。","sm"),Caption("南宋德寿宫遗址博物馆")],2)],4,"start"),
      Text("器物则把注意力带回生活。形制、纹饰与制作的痕迹，让遥远的历史有了可以细看的尺度。"),
      Row([Col([Title("器物里的日常","md"),Text("不必一次看完所有展品，选一件器物，多留一会儿。","sm"),Caption("良渚博物院")],2),Image("\(ShowcasePrograms.liangzhu)","良渚器物")],4,"start"),
      Quote("留一点空白，让眼前的风景慢慢进入记忆。")
    ])
    collection = Col([
      Image("\(ShowcasePrograms.westLake)","西湖暮色"),
      Grid([Image("\(ShowcasePrograms.deshou)","德寿宫院落"),Image("\(ShowcasePrograms.liangzhu)","良渚器物")],2,null,2),
      Title("一座城，几种不同的尺度","lg"),
      Text("远看湖山，近看建筑，再把目光落在一件器物上。", "sm","muted"),
      Grid([
        Col([Image("\(ShowcasePrograms.deshou)","建筑细节"),Title("建筑","md"),Caption("屋檐、院落与空间")],2),
        Col([Image("\(ShowcasePrograms.liangzhu)","器物细节"),Title("器物","md"),Caption("形制、纹饰与工艺")],2)
      ],2,null,3)
    ],2)
    browse = Col([
      Title("沿着自己的兴趣走","lg"),
      Carousel([
        Col([Image("\(ShowcasePrograms.deshou)","德寿宫"),Title("看一处建筑","md"),Text("走进院落，看看屋檐与光。","sm","muted")],2),
        Col([Image("\(ShowcasePrograms.liangzhu)","良渚博物院"),Title("读一件器物","md"),Text("从细节开始，读懂一段历史。","sm","muted")],2),
        Col([Image("\(ShowcasePrograms.westLake)","西湖"),Title("等一场日落","md"),Text("留一段没有安排的时间。","sm","muted")],2)
      ]),
      Divider(),
      Row([Image("\(ShowcasePrograms.deshou)","德寿宫"),Col([Title("南宋德寿宫","md"),Text("先从一处院落开始。","sm","muted")],2)],3,"start"),
      Row([Image("\(ShowcasePrograms.liangzhu)","良渚器物"),Col([Title("良渚博物院","md"),Text("慢慢看见器物的细节。","sm","muted")],2)],3,"start")
    ])
    """
}
