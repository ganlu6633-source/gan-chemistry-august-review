begin;

alter table public.chem_knowledge_cards
  add column if not exists structured_content jsonb not null default '{}'::jsonb;

comment on column public.chem_knowledge_cards.structured_content is
  'Teacher-reviewed, student-facing structured knowledge map. Empty object means the legacy compact card layout.';

update public.chem_knowledge_cards
set
  title = '物质到底分成哪些？从总树干一路分到底',
  core = '先牢记第一根树干：物质按“是否只由一种物质组成”分为纯净物和混合物；纯净物再按“是否只含一种元素”分为单质和化合物。',
  detail = '不要从酸、碱、盐开始猜。每次都从“物质”出发，先判断纯净物或混合物，再对纯净物判断单质或化合物，最后才对化合物做酸、碱、盐、氧化物等更细的分类。同一物质可以同时拥有多个标签，因为每个标签使用的分类标准不同。',
  steps = '["第1问：这份样品里只有一种物质吗？是→纯净物；否→混合物","第2问：如果是纯净物，只含一种元素吗？是→单质；否→化合物","第3问：如果是化合物，它的组成和在水中的行为符合氧化物、酸、碱还是盐的定义？","第4问：题目还要求哪一条横向标准？元数、强弱、溶解性、是否含氧，还是氧化物的性质？"]'::jsonb,
  common_mistakes = '["盐酸、氯水、石灰乳和所有溶液都是混合物，不是纯净物","只含一种元素的样品不一定是单质：O₂和O₃混在一起仍是混合物","含氧化合物不一定是氧化物：NaOH、H₂SO₄和Na₂CO₃都含氧，但都不是氧化物","酸的“几元”看可电离的H⁺数，不是数化学式中所有H","强弱和溶解性是两条不同标准：Ca(OH)₂微溶但是强碱，NH₃·H₂O能存在于水中但是弱碱","金属氧化物不一定是碱性氧化物，非金属氧化物也不一定是酸性氧化物"]'::jsonb,
  micro_example = 'H₂SO₄的完整路径：物质 → 纯净物 → 化合物 → 无机化合物 → 酸；横向再分，它同时是二元酸、强酸、含氧酸和电解质。',
  structured_content = $knowledge$
  {
    "version": 1,
    "intro": "假设你现在完全不记得：先只看下面这棵总树。每次判断都从最上面的‘物质’出发，一层一层往下走，不跳级。",
    "rootTree": {
      "label": "物质",
      "rule": "第一分叉只问：样品中有几种物质？",
      "children": [
        {
          "label": "混合物",
          "rule": "由两种或两种以上物质混合而成，组成通常不固定，各成分保持自己的性质。",
          "examples": ["空气", "盐酸", "氯水", "食盐水", "石灰乳", "漂白粉"]
        },
        {
          "label": "纯净物",
          "rule": "只由一种物质组成，有固定组成，可用一个确定的化学式表示。",
          "examples": ["液氯Cl₂", "蒸馏水H₂O", "氧化钠Na₂O", "碳酸钠Na₂CO₃"],
          "children": [
            {
              "label": "单质",
              "rule": "纯净物中只含一种元素。",
              "examples": ["金属单质：Fe、Cu、Na", "非金属单质：O₂、Cl₂、S、稀有气体He"]
            },
            {
              "label": "化合物",
              "rule": "纯净物中含两种或两种以上元素。",
              "examples": ["H₂O", "CO₂", "H₂SO₄", "NaOH", "NaCl"],
              "children": [
                {
                  "label": "有机化合物",
                  "rule": "高中阶段单独建立有机物体系；含碳不等于一定是有机物。",
                  "examples": ["CH₄", "C₂H₅OH", "CH₃COOH"]
                },
                {
                  "label": "无机化合物",
                  "rule": "本讲重点继续分为氧化物、酸、碱和盐。",
                  "examples": ["CO₂", "HCl", "Ca(OH)₂", "Na₂CO₃"]
                }
              ]
            }
          ]
        }
      ]
    },
    "sections": [
      {
        "title": "常见无机化合物：先分氧化物、酸、碱、盐",
        "summary": "这一层依据组成和在水中电离出的离子判断。",
        "items": [
          {"label": "氧化物", "rule": "只由两种元素组成，且其中一种是氧元素的化合物。", "examples": ["Na₂O", "CO₂", "Al₂O₃", "CO"], "caution": "NaOH、H₂SO₄、Na₂CO₃虽含氧，但都超过两种元素，不是氧化物。"},
          {"label": "酸", "rule": "电离时生成的阳离子全部是H⁺的化合物。", "examples": ["HCl", "H₂SO₄", "H₂CO₃", "CH₃COOH"], "caution": "盐酸是HCl的水溶液，是混合物；说‘HCl是酸和电解质’时，研究对象是HCl这种化合物。"},
          {"label": "碱", "rule": "电离时生成的阴离子全部是OH⁻的化合物。", "examples": ["NaOH", "Ca(OH)₂", "Cu(OH)₂", "NH₃·H₂O"], "caution": "碱不等于可溶性碱；难溶的Cu(OH)₂、Fe(OH)₃仍属于碱。"},
          {"label": "盐", "rule": "由金属阳离子或NH₄⁺与酸根阴离子构成的化合物。", "examples": ["NaCl", "Na₂CO₃", "NH₄Cl", "NaHCO₃"], "caution": "盐的名字中不一定出现‘盐’字，也不是只有食盐NaCl才叫盐。"}
        ]
      },
      {
        "title": "酸要沿三条独立的线分类",
        "summary": "‘几元’、‘强弱’和‘是否含氧’不是同一件事，一种酸会同时得到三个标签。",
        "items": [
          {"label": "按可电离的H⁺个数", "rule": "一元酸：1个；二元酸：2个；多元酸：3个或以上。", "examples": ["一元：HCl、HNO₃、CH₃COOH", "二元：H₂SO₄、H₂CO₃、H₂S", "三元：H₃PO₄"], "caution": "不能直接数化学式中所有H。CH₃COOH有4个H，但只有羧基中的1个H可电离，所以是一元酸。"},
          {"label": "按电离程度", "rule": "强酸在水中近似完全电离；弱酸只部分电离。", "examples": ["强酸：HCl、H₂SO₄、HNO₃", "弱酸：H₂CO₃、H₂S、H₃PO₄、CH₃COOH"], "caution": "强弱看电离程度，不看溶液浓度。稀强酸仍是强酸，浓弱酸仍是弱酸。"},
          {"label": "按是否含氧", "rule": "含氧酸的化学式中含O；无氧酸不含O。", "examples": ["含氧酸：H₂SO₄、HNO₃、H₂CO₃、H₃PO₄", "无氧酸：HCl、HBr、H₂S"]}
        ]
      },
      {
        "title": "碱也要沿三条独立的线分类",
        "summary": "‘几元’看OH⁻数，‘强弱’看电离程度，‘可溶或难溶’看溶解度。",
        "items": [
          {"label": "按可电离的OH⁻个数", "rule": "一元碱产生1个OH⁻；二元碱产生2个OH⁻；三元碱产生3个OH⁻。", "examples": ["一元：NaOH、KOH", "二元：Ca(OH)₂、Ba(OH)₂、Cu(OH)₂", "三元：Fe(OH)₃、Al(OH)₃"]},
          {"label": "按电离程度", "rule": "强碱在水中溶解的部分近似完全电离；弱碱只部分电离。", "examples": ["强碱：NaOH、KOH、Ca(OH)₂、Ba(OH)₂", "弱碱：NH₃·H₂O、Cu(OH)₂、Fe(OH)₃"], "caution": "Ca(OH)₂的溶解度不大，但溶解的部分电离很完全，所以它是强碱。"},
          {"label": "按溶解性", "rule": "可分为易溶碱、微溶碱和难溶碱。", "examples": ["易溶：NaOH、KOH、Ba(OH)₂", "微溶：Ca(OH)₂", "难溶：Mg(OH)₂、Cu(OH)₂、Fe(OH)₃、Al(OH)₃"], "caution": "氨水中的NH₃·H₂O是弱碱，说明‘能与水形成溶液’不等于‘强碱’。"}
        ]
      },
      {
        "title": "氧化物按性质继续分",
        "summary": "先过‘两种元素且一种是O’这道门，再看它和酸、碱反应的性质。",
        "items": [
          {"label": "酸性氧化物", "rule": "能与碱反应生成盐和水的氧化物。", "examples": ["CO₂", "SO₂", "SO₃"]},
          {"label": "碱性氧化物", "rule": "能与酸反应生成盐和水的氧化物。", "examples": ["Na₂O", "CaO", "CuO"]},
          {"label": "两性氧化物", "rule": "既能与强酸反应，又能与强碱反应。", "examples": ["Al₂O₃", "ZnO"]},
          {"label": "不成盐氧化物", "rule": "在通常条件下不表现出上述酸碱性质。", "examples": ["CO", "NO"]},
          {"label": "特殊的过氧化物", "rule": "含有氧氧单键，氧元素常为-1价，不能用普通碱性氧化物规律硬套。", "examples": ["Na₂O₂", "H₂O₂"], "caution": "金属氧化物不一定是碱性：Al₂O₃两性，Na₂O₂是过氧化物；非金属氧化物不一定是酸性：CO、NO是不成盐氧化物。"}
        ]
      },
      {
        "title": "盐的常见继续分类",
        "summary": "先确认是盐，再看酸中的H是否完全被取代，或碱中的OH是否完全被中和。",
        "items": [
          {"label": "正盐", "rule": "酸中可电离的H全部被替换，且不保留OH。", "examples": ["NaCl", "Na₂SO₄", "Na₂CO₃"]},
          {"label": "酸式盐", "rule": "多元酸中可电离的H只被部分替换，阴离子中仍含可电离的H。", "examples": ["NaHCO₃", "NaHSO₄", "NaH₂PO₄"]},
          {"label": "碱式盐", "rule": "碱中的OH未被酸完全中和，盐中仍含OH。", "examples": ["Cu₂(OH)₂CO₃"]},
          {"label": "按溶解性", "rule": "还可分为可溶性盐和难溶性盐，需结合溶解性规律。", "examples": ["可溶：NaCl、KNO₃、(NH₄)₂SO₄", "难溶：AgCl、BaSO₄、CaCO₃"]}
        ]
      },
      {
        "title": "混合物中的分散系",
        "summary": "溶液、胶体和浊液全都是混合物；区分它们的根本标准是分散质粒子直径。",
        "items": [
          {"label": "溶液＜1 nm", "rule": "分散质以分子或离子形式存在，均一、透明、稳定，无丁达尔效应。", "examples": ["NaCl溶液", "蔗糖溶液"]},
          {"label": "胶体1—100 nm", "rule": "分散质粒子尺寸介于溶液和浊液之间，能产生丁达尔效应，相对稳定。", "examples": ["Fe(OH)₃胶体", "淀粉胶体", "雾"]},
          {"label": "浊液＞100 nm", "rule": "粒子较大，通常不稳定，会沉降或分层，包括悬浊液和乳浊液。", "examples": ["泥水", "石灰乳", "油水混合物"], "caution": "胶体宏观上可以看起来均一，但不能因此把它当成溶液。"}
        ]
      },
      {
        "title": "横向分类：电解质与非电解质",
        "summary": "这条线只对化合物分类，与上面的组成树交叉。",
        "items": [
          {"label": "电解质", "rule": "在水溶液中或熔融状态下能够自身电离出可自由移动离子的化合物。", "examples": ["酸", "碱", "盐"]},
          {"label": "非电解质", "rule": "在上述条件下不能自身电离出离子的化合物。", "examples": ["蔗糖", "乙醇"], "caution": "金属能导电，但金属是单质，不能被叫作电解质或非电解质。"}
        ]
      }
    ],
    "workedExamples": [
      {"substance": "H₂SO₄", "path": "纯净物 → 化合物 → 无机化合物 → 酸", "labels": ["二元酸", "强酸", "含氧酸", "电解质"]},
      {"substance": "Ca(OH)₂", "path": "纯净物 → 化合物 → 无机化合物 → 碱", "labels": ["二元碱", "强碱", "微溶碱", "电解质"]},
      {"substance": "NaHCO₃", "path": "纯净物 → 化合物 → 无机化合物 → 盐", "labels": ["酸式盐", "可溶性盐", "电解质"]},
      {"substance": "盐酸", "path": "水和HCl等组成 → 混合物 → 溶液", "labels": ["不是纯净物", "不用一个化学式表示整个溶液"]}
    ],
    "checkpoints": [
      "我能不看答案画出：物质→混合物/纯净物→单质/化合物。",
      "我能把氧化物、酸、碱、盐都挂在‘化合物’下面，不和混合物并列。",
      "我能分别说出酸的元数、强弱、是否含氧三条标准。",
      "我能分别说出碱的元数、强弱、溶解性三条标准。",
      "我能解释为什么Ca(OH)₂微溶却是强碱，也能解释为什么盐酸是混合物。"
    ]
  }
  $knowledge$::jsonb,
  review_status = 'approved',
  updated_at = now()
where skill_id = 'H1_CLASSIFY';

update public.chem_questions
set review_status = 'retired', updated_at = now()
where skill_id = 'H1_CLASSIFY'
  and review_status = 'approved';

insert into public.chem_questions
  (id, mother_id, skill_id, level, grade_band, stem, options, correct_option, explanation, scaffold, review_status, scope_status, source_kind)
values
  ('QCLS_ZERO_01','MCLS_ZERO_01','H1_CLASSIFY',1,'高一','物质分类的第一个分叉是','["单质和化合物","纯净物和混合物","酸和碱","金属和非金属"]'::jsonb,1,'必须从根部开始：先按“样品中有几种物质”分为纯净物和混合物。只有确认为纯净物后，才继续分单质和化合物。','从“物质”这个总起点开始，只问样品中有几种物质。','approved','IN','teacher_original'),
  ('QCLS_ZERO_02','MCLS_ZERO_02','H1_CLASSIFY',1,'高一','下列属于纯净物的是','["空气","盐酸","液氯","石灰乳"]'::jsonb,2,'液氯只由Cl₂一种物质组成，是纯净物。空气含多种气体，盐酸是HCl的水溶液，石灰乳是悬浊液，三者都是混合物。','“液”只表示状态，不等于“溶液”。','approved','IN','teacher_original'),
  ('QCLS_ZERO_03','MCLS_ZERO_03','H1_CLASSIFY',1,'高一','已知某物质是纯净物，下一步应根据什么区分单质和化合物','["是否含氧","是否能导电","所含元素种类是1种还是2种及以上","是固体还是液体"]'::jsonb,2,'在纯净物这一前提下，只含一种元素的是单质，含两种或以上元素的是化合物。','先确认前提是纯净物，再数元素种类。','approved','IN','teacher_original'),
  ('QCLS_ZERO_04','MCLS_ZERO_04','H1_CLASSIFY',1,'高一','下列“从总类到子类”的路径正确的是','["H₂SO₄：混合物→酸", "H₂SO₄：纯净物→单质→酸", "H₂SO₄：纯净物→化合物→无机化合物→酸", "H₂SO₄：纯净物→氧化物→酸"]'::jsonb,2,'H₂SO₄是一种有固定组成的物质，属于纯净物；它含H、S、O三种元素，是化合物；在常见无机化合物中属于酸。','每一个箭头都要能用定义说明。','approved','IN','teacher_original'),
  ('QCLS_ZERO_05','MCLS_ZERO_05','H1_CLASSIFY',1,'高一','判断一种酸是一元酸、二元酸还是多元酸，根本依据是','["化学式中所有H原子的个数","每个酸分子可电离出的H⁺个数","酸溶液的浓度","酸是否含氧"]'::jsonb,1,'酸的元数取决于每个酸分子能够电离出的H⁺个数。例如CH₃COOH有4个H，但只有1个羧基氢可电离，所以是一元酸。','“几元”数的是可电离H⁺，不是字面上所有H。','approved','IN','teacher_original'),
  ('QCLS_ZERO_06','MCLS_ZERO_06','H1_CLASSIFY',1,'高一','Ca(OH)₂按可电离的OH⁻个数分类，属于','["一元碱","二元碱","三元碱","不是碱"]'::jsonb,1,'1个Ca(OH)₂式量单位可对应产生2个OH⁻，因此是二元碱。它同时还是强碱和微溶碱。','看化学式中可电离OH⁻的个数。','approved','IN','teacher_original'),
  ('QCLS_ZERO_07','MCLS_ZERO_07','H1_CLASSIFY',1,'高一','下列关于碱的强弱与溶解性的说法正确的是','["难溶的碱一定是弱碱","强碱一定大量溶于水", "Ca(OH)₂微溶，但其溶解的部分电离完全，属于强碱", "NH₃·H₂O能存在于水中，所以是强碱"]'::jsonb,2,'强弱看电离程度，溶解性看能溶解多少，二者是两条独立标准。Ca(OH)₂溶解度不大，但属于强碱。','把“溶多少”和“溶解后电离多少”分开。','approved','IN','teacher_original'),
  ('QCLS_ZERO_08','MCLS_ZERO_08','H1_CLASSIFY',1,'高一','溶液、胶体和浊液的共同点是','["都是纯净物","都是混合物和分散系","都有丁达尔效应","分散质粒子直径都小于1 nm"]'::jsonb,1,'溶液、胶体和浊液都由分散质和分散剂组成，因此都是混合物。它们的根本区别是分散质粒子直径不同。','先问它们是一种物质还是多种物质组成。','approved','IN','teacher_original'),
  ('QCLS_ZERO_09','MCLS_ZERO_09','H1_CLASSIFY',2,'高一','H₂SO₄可以同时得到的一组正确标签是','["一元酸、弱酸、无氧酸","二元酸、强酸、含氧酸","二元碱、强碱、可溶碱","氧化物、强酸、电解质"]'::jsonb,1,'H₂SO₄可电离出2个H⁺，是二元酸；在水中作为强电解质，是强酸；化学式含O，是含氧酸。','元数、强弱、含氧与否分别判断。','approved','IN','teacher_original'),
  ('QCLS_ZERO_10','MCLS_ZERO_10','H1_CLASSIFY',2,'高一','Ca(OH)₂的完整分类中正确的是','["一元碱、弱碱、难溶碱","二元碱、强碱、微溶碱","二元酸、强酸、含氧酸","盐、可溶盐、电解质"]'::jsonb,1,'Ca(OH)₂可产生2个OH⁻，属于二元碱；溶解的部分电离完全，是强碱；它在水中微溶。','三条轴分别看，不要用溶解性推强弱。','approved','IN','teacher_original'),
  ('QCLS_ZERO_11','MCLS_ZERO_11','H1_CLASSIFY',2,'高一','下列氧化物性质分类正确的是','["CO₂—碱性氧化物", "Na₂O—酸性氧化物", "Al₂O₃—两性氧化物", "CO—酸性氧化物"]'::jsonb,2,'Al₂O₃既能和强酸反应，又能和强碱反应，属于两性氧化物。CO₂是酸性氧化物，Na₂O是碱性氧化物，CO是不成盐氧化物。','先过氧化物定义，再看与酸碱反应的性质。','approved','IN','teacher_original'),
  ('QCLS_ZERO_12','MCLS_ZERO_12','H1_CLASSIFY',2,'高一','下列盐的分类正确的是','["NaHCO₃—酸式盐", "Na₂CO₃—酸式盐", "Cu₂(OH)₂CO₃—正盐", "HCl—盐"]'::jsonb,0,'NaHCO₃中的HCO₃⁻仍保留可电离的H，属于酸式盐。Na₂CO₃是正盐，Cu₂(OH)₂CO₃是碱式盐，HCl是酸。','看多元酸的H是否已经全部被取代。','approved','IN','teacher_original'),
  ('QCLS_ZERO_13','MCLS_ZERO_13','H1_CLASSIFY',2,'高一','区分Fe(OH)₃胶体和FeCl₃溶液最有效的方法是','["闻气味","用一束光通过并观察是否有光亮通路","只看颜色","加水后称量"]'::jsonb,1,'胶体粒子能散射光，产生丁达尔效应；真溶液不产生这条光亮通路。','题目考查胶体的特征现象。','approved','IN','teacher_original'),
  ('QCLS_ZERO_14','MCLS_ZERO_14','H1_CLASSIFY',2,'高一','关于HCl和盐酸，下列说法正确的是','["HCl和盐酸都是纯净物", "HCl是化合物，盐酸是HCl的水溶液、属于混合物", "HCl是单质，盐酸是化合物", "盐酸可以用HCl一个化学式表示整个溶液"]'::jsonb,1,'HCl表示一种有固定组成的化合物；盐酸含HCl、H₂O及水合离子，是混合物。','把物质本身与它的水溶液分开。','approved','IN','teacher_original'),
  ('QCLS_ZERO_15','MCLS_ZERO_15','H1_CLASSIFY',3,'高一','现有空气、Cl₂、CO₂、NaOH、NaHCO₃五种样品，按顺序它们分别属于','["混合物、单质、氧化物、碱、盐", "纯净物、化合物、酸、碱、氧化物", "混合物、单质、盐、氧化物、酸", "溶液、混合物、单质、盐、碱"]'::jsonb,0,'空气含多种气体，是混合物；Cl₂是非金属单质；CO₂是酸性氧化物；NaOH是碱；NaHCO₃是酸式盐。','五种样品分别从总树根部往下走。','approved','IN','teacher_original'),
  ('QCLS_ZERO_16','MCLS_ZERO_16','H1_CLASSIFY',3,'高一','一份样品中同时含O₂和O₃，该样品的分类是','["单质，因为只含氧元素","化合物，因为含两种分子","混合物，因为同时含O₂和O₃两种物质","氧化物，因为含氧"]'::jsonb,2,'判断单质前必须先是纯净物。O₂和O₃是两种不同物质，混在一起就是混合物，即使样品中只含氧元素。','先数物质种类，再数元素种类。','approved','IN','teacher_original'),
  ('QCLS_ZERO_17','MCLS_ZERO_17','H1_CLASSIFY',3,'高一','下列推理正确的是','["金属氧化物都是碱性氧化物","非金属氧化物都是酸性氧化物", "Al₂O₃是金属氧化物，但它是两性氧化物", "CO含氧，所以它是酸性氧化物"]'::jsonb,2,'元素类别与酸碱性质是两条不同的分类线。Al₂O₃是金属氧化物，但既能和强酸又能和强碱反应，是两性氧化物。','不要用“金属/非金属”直接替代性质判定。','approved','IN','teacher_original'),
  ('QCLS_ZERO_18','MCLS_ZERO_18','H1_CLASSIFY',3,'高一','下列关于酸的说法正确的是','["浓度大的酸一定是强酸","能电离出多个H⁺的酸一定是强酸","稀HCl仍是强酸，浓CH₃COOH仍是弱酸","含氧酸都是强酸"]'::jsonb,2,'强弱只由在水中的电离程度判定，与这份溶液浓或稀不是同一标准。HCl是强酸，CH₃COOH是弱酸。','把“酸本身的强弱”与“某份溶液的浓度”分开。','approved','IN','teacher_original'),
  ('QCLS_ZERO_19','MCLS_ZERO_19','H1_CLASSIFY',4,'高一','对NaHCO₃的分类路径和横向标签都正确的是','["纯净物→化合物→盐；酸式盐、可溶性盐、电解质", "纯净物→氧化物；碱性氧化物、强电解质", "混合物→溶液；一元酸、含氧酸", "纯净物→酸；一元酸、弱酸"]'::jsonb,0,'NaHCO₃有固定组成，是纯净物和化合物；由Na⁺与HCO₃⁻构成，是盐；HCO₃⁻仍含可电离氢，属于酸式盐，同时是可溶性盐和电解质。','先画纵向路径，再补横向标签。','approved','IN','teacher_original'),
  ('QCLS_ZERO_20','MCLS_ZERO_20','H1_CLASSIFY',4,'高一','下列四种物质的多重分类全部正确的是','["H₃PO₄：三元强酸、含氧酸；Ca(OH)₂：二元弱碱、微溶碱", "HCl：一元强酸、无氧酸；Ca(OH)₂：二元强碱、微溶碱", "CO：酸性氧化物；Al₂O₃：碱性氧化物", "Na₂CO₃：酸式盐；NaHCO₃：正盐"]'::jsonb,1,'HCl只可电离出1个H⁺，是一元强酸，且不含O；Ca(OH)₂是二元强碱和微溶碱。H₃PO₄是弱酸，CO不成盐，Al₂O₃两性，Na₂CO₃是正盐而NaHCO₃是酸式盐。','每个标签都回到对应的唯一标准检查。','approved','IN','teacher_original')
on conflict (id) do update set
  mother_id = excluded.mother_id,
  skill_id = excluded.skill_id,
  level = excluded.level,
  grade_band = excluded.grade_band,
  stem = excluded.stem,
  options = excluded.options,
  correct_option = excluded.correct_option,
  explanation = excluded.explanation,
  scaffold = excluded.scaffold,
  review_status = 'approved',
  scope_status = 'IN',
  source_kind = 'teacher_original',
  updated_at = now();

commit;
