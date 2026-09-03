import Foundation

/// 암구호(passphrase)에 쓰는 단어 목록.
///
/// 짧고 흔하고 철자를 헷갈리지 않는 영어 단어만 모았습니다.
/// 중복이 섞여 있어도 `words` 에서 걸러지고, 엔트로피는 **걸러낸 뒤의 실제 개수**로 계산하므로
/// 목록을 늘리거나 줄여도 세기 표시가 부풀려지지 않습니다.
public enum WordList {

    /// 중복을 없애고 정렬한 단어들.
    public static let words: [String] = {
        var seen = Set<String>()
        var result: [String] = []
        for raw in rawWords.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let word = String(raw)
            guard word.count >= 3, word.allSatisfy({ $0.isLowercase && $0.isASCII }) else { continue }
            if seen.insert(word).inserted {
                result.append(word)
            }
        }
        return result.sorted()
    }()

    private static let rawWords = """
    able about above absent accept across action active actor adapt
    admit adopt adult advice affair afford after again agent agree
    ahead alarm album alert alike alive allow almost alone along
    alpha alter among amount anchor ancient angle animal ankle annual
    answer anxiety apart apple apply april arcade arch area argue
    arise armor army around arrive arrow artist aside asset assist
    assume atlas attach attend author autumn avenue avoid awake award
    aware away bacon badge bagel baker balance balcony ball
    bamboo banana banner barrel basic basket batch beach beacon beam
    bean bear beauty become beetle before begin behind being belief
    belong below bench benefit berry beside better beyond bicycle bike
    binder birch bird birth biscuit bishop bison bitter black blade
    blanket blast blend bless blind block blossom blue board boat
    bonus book boost border borrow bottle bottom bounce bowl brain
    branch brave bread break breeze brick bridge brief bright bring
    broad bronze brook brother brown brush bubble bucket budget buffalo
    build bullet bundle bunny burden burst butter button buyer cabin
    cable cactus cage cake calm camera camp canal candle candy canoe
    canvas canyon capital captain carbon cargo carpet carrot carry carve
    castle casual catch cattle cause cave cedar celery cellar cement
    center cereal chain chair chalk chance change chapter charm chart
    chase cheap check cheese cherry chess chest chicken chief child
    chilly chimney choice choose chorus cider circle city civil
    claim clamp clarity classic clay clean clear clever cliff climb
    clinic clock close cloth cloud clover clown club coach coast
    cobalt cocoa coffee coin cold collar colony color column combine
    comedy comfort comic common compass concert concrete connect consider constant
    contact convert cookie cool copper coral corner cotton couch cough
    count country couple courage course cousin cover coyote crack cradle
    craft crane crash crater crawl crayon cream create credit creek
    crew cricket crimson crisp cross crowd crown cruise crumb crystal
    cube cuckoo cupboard curious current curtain curve custom cycle daily
    dairy damage dance danger daring dark dawn daylight deal debate
    decade decide declare decor deep defend define degree delay delight
    deliver demand denim dense depart depend deposit depth desert design
    desire desk detail detect develop device devote diamond diary diet
    differ digital dinner direct dirt disco discover dish distance divide
    doctor dollar dolphin domain donate donkey door double dough dove
    dozen draft dragon drama draw dream dress drift drink drive
    drop drum duck dune during dusk dust duty eager
    eagle early earn earth easily east easy echo edge editor
    effort eight either elbow elder electric elegant element elephant eleven
    elite else email embark emerge emotion empty enable enact
    endless energy engage engine enjoy enough enrich ensure enter entire
    entry equal equip error escape essay estate ethic even
    event ever every evolve exact exam example exceed excite exist
    exit expand expect expert explain export expose extend extra fabric
    face factor fade fair falcon fall family famous fancy fantasy
    farm fashion fast fault favor feather feature fence fern festival
    fever fiber fiction field fifteen figure filter final find finger
    finish fire first fiscal fish fitness five flag flame
    flash flat flavor flee flight float floor flour flower fluid
    flush focus fold follow food foot force forest forget
    fork form fortune forum forward fossil foster found four
    frame free fresh friend fringe frog front frost fruit fuel
    full future gadget gain galaxy gallery game garage garden
    garlic gather gauge gaze gear general gentle genuine gesture
    ghost giant gift ginger giraffe girl give glad glance glass
    glide globe glory glove glow goal goat gold golf good
    goose grace grade grain grand grant grape graph grass gravity
    gray great green grid grill grip grocery groove ground group
    grow guard guess guest guide guitar habit hail hair half
    hall hammer hamster hand happy harbor hard harvest have
    hawk hazard head health heart heavy hedge height hello helmet
    help herb here hero hidden high hill hint hire history
    hobby hockey hold hole holiday hollow home honey honor hood
    hope horizon horn horse hospital host hotel hour house human
    humble humor hundred hunger hunt hurry icon idea ideal
    identify idle image impact import improve impulse inch include income
    increase indeed index indoor infant inform inner input insect inside
    insight inspire install instant intact intend invest invite iron island
    issue item ivory jacket jaguar jazz jeans jelly jewel
    join joke journey judge juice jump jungle junior
    just kangaroo keen keep kernel ketchup key kick kind king
    kiss kitchen kite kitten knee knife knock know koala label
    labor ladder lake lamp land language laptop large laser last
    later laugh launch laundry lava law layer lazy leader leaf
    league learn leave lecture left legend lemon lend length lens
    leopard lesson letter level liberty library license life lift light
    like lily limit line link lion liquid list listen little
    live lizard load loan lobby local lock logic lonely long
    loop lord lose lotus loud love lower loyal luck lunar
    lunch lung luxury machine magic magnet maid mail main major
    make mammal manage mango manner mansion map marble march margin
    marine market marry mask master match matter maze meadow meal
    mean measure meat medal media medium meet melody melon member
    memory mention menu mercy merge merit merry mesh message metal
    method middle midnight might mild milk mind mineral minute mirror
    mission mist mobile model modern modify moment monitor monkey
    month moon moral morning mosaic motion motor mountain mouse move
    movie much muffin multiple muscle museum music must mutual myself
    mystery napkin narrow nation native nature near neat neck need
    nephew nerve nest network never new news next
    nice night noble noise none noodle noon normal north nose
    note notice novel now nuclear number nurse oak
    object observe ocean october odor offer office often oil okay
    old olive omit once one onion online only open
    opera opinion orange orbit orchard order organ origin other ounce
    outdoor outer output outside oval oven over owl own
    oxygen oyster pace pack paddle page pair palace palm panda
    panel panic paper parade parent park parrot part party pass
    past pasta patch path patient pattern pause pave peace peach
    peak peanut pear pearl pencil people pepper perfect permit person
    phone photo phrase piano picnic picture piece pigeon pilot pine
    pink pioneer pipe pitch pizza place plain plan planet plant
    plastic plate play please pledge plenty plot plug plum pocket
    poem point polar police policy polish pond pony pool
    popular portion position possible post potato pottery pound powder power
    praise prefer prepare present press pretty prevent price pride primary
    print prior prison privacy prize problem process produce profit program
    project promise proof proper protect proud prove public pudding pull
    pulse pumpkin punch pupil puppy purchase pure purple purpose push
    puzzle pyramid quality quantum quarter queen quest question quick quiet
    quilt quit quiz quote rabbit raccoon race radar radio raft
    rail rain raise rally ranch range rapid rare rate rather
    raven razor reach react read ready real reason rebel recall
    receive recipe record recover recycle reduce reflect refuse region regret
    regular reject relax release relief rely remain remember remind remove
    render renew rent repair repeat replace reply report request rescue
    research resist resort resource respect response rest result retire return
    reveal review reward rhythm ribbon rice rich ride ridge rifle
    right rigid ring ripple rise risk ritual river road roast
    robot rock rocket rodeo role roll roof room root
    rope rose rotate rough round route royal rubber ruby rule
    run rural rush safe sail salad salmon salon salt
    sample sand satisfy sauce sausage save say scale scan scarf
    scatter scene schedule scheme school science scissors scope score scout
    screen script search season second secret section secure seed
    seek seem select sell send senior sense sentence series serve
    service session settle seven shadow shaft shallow shape share sharp
    shed sheep sheet shelf shell shield shift shine ship shirt
    shock shoe shoot shop short shoulder show shrimp shuffle side
    siege sight sign silent silk silver similar simple since sing
    single sister site situate six size skate sketch ski skill
    skin skirt sky slab sleep slice slide slight slim slogan
    slope slot slow small smart smile smoke smooth snack snake
    snow soap soccer social sock soda soft solar soldier solid
    solution solve some song soon sorry sort soul sound soup
    source south space spare spark speak special speed spell spend
    sphere spice spider spin spirit split spoon sport spot spray
    spread spring square squeeze stable stadium staff stage stairs stamp
    stand star start state station stay steady steam steel stem
    step stereo stick still stock stomach stone stool stop storm
    story stove strap street stress strike string strong studio study
    stuff style subject submit subway succeed such sudden sugar suggest
    suit summer summit sunny sunset super supply support suppose surface
    surge surprise survey survive sweet swim swing switch sword symbol
    symptom syrup system table tackle tail talent talk tall
    tank tape target task taste taxi teach team tell
    temple tennis tent term test text thank theme theory thing
    think third thirty thought three thrive throw thumb thunder ticket
    tidy tiger tight timber time tiny tip tissue title toast
    today together toilet token tomato tone tongue tonight tool
    tooth top topic torch total touch tourist toward tower town
    track trade traffic trail train transfer trap travel tray treat
    tree trend trial tribe trick trigger trip trophy trouble truck
    true trust truth try tube tuition tumble tuna tunnel
    turkey turn turtle twelve twenty twice twin twist type typical
    ugly ultimate umbrella uncle under undo unfair unfold uniform union
    unique unit unlock until unusual update upgrade upon upper upset
    urban urge usage use useful usual utility vacant vacuum vague
    valid valley value valve vanish vapor variety various vast vault
    vegetable vehicle velvet vendor venture venue verb verify version vessel
    veteran viable vibrant victory video view village vintage violet virtual
    virus visa visible vision visit visual vital vivid vocal voice
    volcano volume vote voyage wage wagon wait wake walk wall
    walnut want warm warn wash waste watch water wave weak
    wealth weapon wear weather weave wedding weekend weight welcome well
    west whale wheat wheel when where which while whisper white
    whole wide width wild will win wind window wine wing
    winter wire wisdom wise wish witness wolf woman wonder wood
    wool word work world worry worth wrap wrist write wrong
    yard year yellow yes yesterday yield yoga young youth zebra
    zero zone
    """
}
