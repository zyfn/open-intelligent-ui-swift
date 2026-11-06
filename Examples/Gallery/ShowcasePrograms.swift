import Foundation

enum ShowcasePrograms {
    static let deshou = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8c/Deshou_Palace.jpg/960px-Deshou_Palace.jpg"
    static let liangzhu = "https://upload.wikimedia.org/wikipedia/commons/thumb/2/28/Liangzhu_Museum%2C_2019-07-07_04.jpg/960px-Liangzhu_Museum%2C_2019-07-07_04.jpg"
    static let westLake = "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/West_Lake_%28Hangzhou%29_sunset_2016_January.jpg/960px-West_Lake_%28Hangzhou%29_sunset_2016_January.jpg"
    static let photoResources = [("deshou-palace", deshou), ("liangzhu-museum", liangzhu), ("west-lake", westLake)]

    // 2026-11-03 UTC test-host receipts: MapKit-native coordinates and matching FlyAI POI images.
    // Images stay remote; no third-party raster asset is redistributed with the library.
    static let placesMap = """
    root = Col([Title("杭州历史地点", "xl"), Text("地点与坐标来自MapKit查询快照，图片来自对应景点资料；不提供实时开放或路线规划。", "sm", "muted"), Map([MapMarker("南宋德寿宫遗址博物馆",30.238678,120.173273,"博物馆","landmark","deshou"),MapMarker("胡雪岩旧居（胡雪岩故居）",30.237273,120.172906,"历史建筑","landmark","huxueyan")],false,$selectedPlace,540,[Carousel([Card([ImageText(deshouPlace,"leading")],"outline",3,2),Card([ImageText(huxueyanPlace,"leading")],"outline",3,2)],320,3,$selectedPlace,["deshou","huxueyan"])],true)])
    $selectedPlace = "deshou"
    deshouPlace = {image:{url:"https://img.alicdn.com/imgextra/i1/6000000006632/O1CN01AEaXtv1yrVVKfCqT1_!!6000000006632-2-fliggyimage.png",alt:"南宋德寿宫遗址博物馆实景（FlyAI景点资料图）"},title:"南宋德寿宫遗址博物馆",subtitle:"中国浙江省杭州市上城区望江路228-264号(江城路地铁站E口步行460米)"}
    huxueyanPlace = {image:{url:"https://img.alicdn.com/imgextra/i4/O1CN01H2nHQX1eMY8l7wyno_!!0-alitrip.jpg",alt:"胡雪岩旧居（胡雪岩故居）实景（FlyAI景点资料图）"},title:"胡雪岩旧居（胡雪岩故居）",subtitle:"中国浙江省杭州市上城区元宝街18号"}
    """

    static let editorial = """
    root = Col([
      Caption("城市手记 · 排版示例"),
      Title("杭州，沿着历史与湖山慢慢看", "xl"),
      Text("先看宫城与器物，再把脚步放慢。从南宋历史、良渚文化和西湖风景出发，可以找到不同的观察线索。"),
      Image("\(westLake)","西湖暮色",1.7778,"lg","cover",true),
      Caption("西湖暮色 · Morio / CC BY-SA 4.0"),
      Title("两条值得展开的线索", "lg"),
      Carousel([
        ImageText({image:{url:"\(deshou)",alt:"德寿宫建筑"},title:"南宋宫城",subtitle:"建筑 · 遗址"},"top"),
        ImageText({image:{url:"\(liangzhu)",alt:"良渚博物馆藏陶罐"},title:"良渚器物",subtitle:"纹饰 · 工艺"},"top")
      ],244,4),
      Title("把目光留给具体的地方", "lg"),
      ImageText({image:{url:"\(deshou)",alt:"南宋德寿宫建筑"},title:"1. 南宋德寿宫遗址博物馆",badge:"历史遗址",subtitle:"南宋历史 · 宫廷建筑",body:"可以先从建筑细节与遗址展示入手，再结合展览中的说明，了解南宋临安的历史。让现场看到的空间关系，与文字中的历史线索相互印证。",caption:"出发前请核对当天开放与预约安排。"},"leading",[
        Citation([{title:"德寿宫照片与说明",url:"https://commons.wikimedia.org/wiki/File:Deshou_Palace.jpg"},{title:"德寿宫资料",url:"https://commons.wikimedia.org/wiki/Category:Deshou_Palace"}])
      ]),
      Divider(),
      ImageText({image:{url:"\(liangzhu)",alt:"良渚博物馆藏刻符陶罐"},title:"2. 良渚博物院",subtitle:"史前文明 · 器物",body:"把注意力放在器物的形制、纹饰和制作工艺上，再结合展览说明了解良渚文化。照片中的刻符陶罐，也适合作为观察细节的起点。",caption:"参观内容与安排以发布方信息为准。"},"leading",[
        Citation([{title:"良渚博物馆藏品照片",url:"https://commons.wikimedia.org/wiki/File:Liangzhu_Museum,_2019-07-07_04.jpg"}])
      ]),
      Divider(),
      ImageText({image:{url:"\(westLake)",alt:"西湖日落"},title:"3. 西湖",subtitle:"湖山风景 · 步行观察",body:"留出一段步行时间，观察湖面、岸线与远处建筑。黄昏光线与白天不同，适合放慢脚步，把照片与亲眼看到的空间关系放在一起。"},"leading",[
        Citation([{title:"西湖照片",url:"https://commons.wikimedia.org/wiki/File:West_Lake_(Hangzhou)_sunset_2016_January.jpg"}])
      ]),
      Text("图片：Takashishin、Siyuwj、Morio · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)，经 Wikimedia 提供的缩略图。本文为 UI 内容示例，不提供实时开放或票务信息。","xs","muted")
    ])
    """

    static let transport = """
    root = Col([
      Caption("交通展示 · 固定演示数据"),
      Title("看清出发、抵达与中转", "xl"),
      Text("以下班次、票价、时间与链接均为组件测试数据，不代表实际可预订行程。","sm","muted"),
      Title("直达", "lg"),
      TransportCard(flight), TransportCard(train),
      Title("中转与联程", "lg"),
      TransportCard(connection), TransportCard(mixed)
    ])
    flight = {id:"flight-direct",legs:[{mode:"flight",from:"北京大兴",to:"杭州萧山",departureTime:"07:25",arrivalTime:"09:25",departureDate:"2026-11-12",arrivalDate:"2026-11-12",fromCode:"PKX",toCode:"HGH",toTerminal:"T3",carrier:"示例航空",serviceNumber:"DEMO123",durationText:"2小时"}],durationText:"2小时",priceText:"¥580 起",priceNote:"演示票价 · 条件待核对",bookingURL:"/journeys/flight-direct",actionLabel:"查看票价"}
    train = {id:"train-direct",legs:[{mode:"train",from:"杭州东",to:"上海虹桥",departureTime:"09:00",arrivalTime:"09:58",departureDate:"2026-11-12",arrivalDate:"2026-11-12",carrier:"示例铁路",serviceNumber:"G0001（演示）",durationText:"58分钟"}],durationText:"58分钟",priceText:"¥73",priceNote:"二等座 · 演示票价",bookingURL:"/journeys/train-direct"}
    connection = {id:"flight-transfer",legs:[{id:"f1",mode:"flight",from:"北京大兴",to:"成都天府",departureTime:"08:00",arrivalTime:"11:00",departureDate:"2026-11-12",arrivalDate:"2026-11-12",carrier:"示例航空",serviceNumber:"DEMO201"},{id:"f2",mode:"flight",from:"成都天府",to:"昆明长水",departureTime:"12:40",arrivalTime:"14:20",departureDate:"2026-11-12",arrivalDate:"2026-11-12",carrier:"示例航空",serviceNumber:"DEMO202"}],connections:[{afterLeg:0,location:"成都天府",durationText:"1小时40分",notice:"演示：请核对中转与行李规则。"}],durationText:"6小时20分",priceText:"¥980 起",priceNote:"演示票价",bookingURL:"/journeys/flight-transfer"}
    mixed = {id:"mixed-overnight",legs:[{id:"m1",mode:"train",from:"上海虹桥",to:"杭州东",departureTime:"21:10",arrivalTime:"22:08",departureDate:"2026-11-12",arrivalDate:"2026-11-12",carrier:"示例铁路",serviceNumber:"G0002（演示）",bookingURL:"/journeys/mixed/train"},{id:"m2",mode:"flight",from:"杭州萧山",to:"成都天府",departureTime:"08:00",arrivalTime:"11:00",departureDate:"2026-11-13",arrivalDate:"2026-11-13",departureZone:"北京时间",arrivalZone:"北京时间",carrier:"示例航空",serviceNumber:"DEMO301",bookingURL:"/journeys/mixed/flight"}],connections:[{afterLeg:0,location:"杭州东 → 杭州萧山",durationText:"9小时52分",changeStation:true,notice:"需自行安排换站；跨日接续。此数据仅展示组件。"}],durationText:"13小时50分",separateTickets:true}
    """

    static let timeline = """
    root = Col([Title("按时间展开一天", "xl"),Caption("杭州行程 · 固定演示安排"),SegmentedControl($day,["第一天","第二天"],true),Button("展开首个节点",@Set($firstOpen,true),"ghost"),List($day == "第一天" ? firstDay : secondDay,"none",true)])
    $day = "第一天"
    $firstOpen = false
    firstDay = [
      ListItem("南宋德寿宫遗址博物馆","历史遗址 · 示例停留90分钟","09:00",[Disclosure("查看安排",[Text("从建筑与遗址展示开始，现场开放信息请另行核对。")],$firstOpen)],"deshou"),
      ListItem("南宋御街","街区观察 · 示例停留60分钟","11:00",[Disclosure("街区安排",[Text("步行观察街道与沿线建筑，安排只是排版示例。")])],"song-street"),
      ListItem("湖滨步行","湖山风景 · 示例停留90分钟","14:00",[Disclosure("步行安排",[Text("按自己的节奏调整停留，保留休息时间。")])],"lake-walk"),
      ListItem("西湖暮色","摄影观察 · 示例停留60分钟","17:00",[Disclosure("傍晚安排",[Text("本文不预测天气或实时日落时间。")])],"west-lake")
    ]
    secondDay = [ListItem("良渚博物院","器物与工艺 · 示例安排","09:30",[Disclosure("查看说明",[Text("根据实际开放与预约条件调整安排。")])],"liangzhu"),ListItem("整理观察记录","回顾与比较","14:00",[Text("把图像与文字记录放在一起，留下自己的判断。")],"notes")]
    """

    static let patterns = """
    root = Col([Title("按需展开与进度", "lg"),Slider($value,0,100,1,"完成比例","%"),Progress($value,100,"处理进度"),Row([Button("增加进度",@Set($value,$value >= 100 ? 100 : $value + 10),"outline"),Button("重置",@Set($value,0),"ghost")],3,"center","start",true),Disclosure("补充说明",[Text("折叠详情与进度使用原生控件，具体内容和真实进度由调用方提供。")],$expanded),Button("展开说明",@Set($expanded,true),"outline")])
    $value = 45
    $expanded = false
    """
}
