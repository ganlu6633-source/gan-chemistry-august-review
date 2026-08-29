-- Generated from content/knowledge/h1_opening_knowledge_cards.json.
-- Canonical JSON SHA-256: 2f25688c527b81e24b5a4d1c442116f3744c52dbfbf1e69f4d186995ea88fcf8
-- Contains only reviewed, student-facing knowledge content; no source paths,
-- question text, answer assets, access data, or unpublished release metadata.

begin;

insert into public.chem_skills (
  id, title, module_id, grade_band, max_level, exam_importance, exam_depth,
  prerequisites, level_criteria, active
)
values
  (
    'H1_REACTION_CLASSIFICATION', '物质转化与化学反应分类', 'H1-SUJIAO-B1-U1',
    '高一', 3, 5, 3, array[]::text[],
    '[{"level":1,"studentFacingGoal":"能辨认物质类别与基本反应类型","requiredAbility":"依据组成和反应物、生成物特征完成基础分类"},{"level":2,"studentFacingGoal":"能在新情境中判断转化与反应分类","requiredAbility":"结合反应条件、价态和离子变化迁移分类规则"},{"level":3,"studentFacingGoal":"能综合判断多步转化及分类依据","requiredAbility":"同时核对物质类别、反应类型和边界条件并说明理由"}]'::jsonb,
    true
  ),
  (
    'H1_SOLUTION_CONCENTRATION', '物质的量浓度、配制、稀释与误差', 'H1-SUJIAO-B1-U1',
    '高一', 3, 5, 3, array[]::text[],
    '[{"level":1,"studentFacingGoal":"能辨认物质的量浓度及配制步骤","requiredAbility":"能用c=n/V完成基础换算并识别规范操作"},{"level":2,"studentFacingGoal":"能处理稀释、混合与配制误差","requiredAbility":"能用溶质守恒和误差方向分析变化情境"},{"level":3,"studentFacingGoal":"能综合解决浓度配制与实验评价","requiredAbility":"能串联计算、实验步骤和误差判断完成综合分析"}]'::jsonb,
    true
  )
on conflict (id) do update set
  title = excluded.title,
  module_id = excluded.module_id,
  grade_band = excluded.grade_band,
  max_level = excluded.max_level,
  exam_importance = excluded.exam_importance,
  exam_depth = excluded.exam_depth,
  prerequisites = excluded.prerequisites,
  level_criteria = excluded.level_criteria,
  active = true,
  updated_at = now();

with reviewed_cards as (
  select value as card
  from jsonb_array_elements($h1_opening_cards$[
  {
    "id": "KC_H1_REACTION_CLASSIFICATION_ZERO",
    "skill_id": "H1_REACTION_CLASSIFICATION",
    "title": "物质怎样一步步转化，反应怎样准确分类",
    "core": "先看物质能不能在一次反应中完成转化，再写方程式，最后按反应物和生成物的结构分类。",
    "detail": "五个细知识点按总树、可行性、四种基本类型、边界和流程综合完整展开。",
    "steps": [
      "常见物质转化关系与知识网络",
      "一步转化的可行性与反应条件",
      "化合、分解、置换、复分解反应",
      "四种基本反应类型的边界与反例",
      "转化流程与反应分类综合"
    ],
    "common_mistakes": [
      "跳过反应条件直接连箭头",
      "看到单质就误判为置换反应",
      "把所有反应硬塞进四种基本类型"
    ],
    "micro_example": "Ca→CaO→Ca(OH)₂→CaCO₃：逐箭头写方程式，再逐步分类。",
    "asset": {
      "type": "structured_knowledge",
      "contractVersion": 4,
      "studentSourceHidden": true
    },
    "review_status": "approved",
    "structured_content": {
      "version": 4,
      "intro": "先看物质能不能在一次反应中完成转化，再写方程式，最后按反应物和生成物的结构分类。",
      "overview": [
        "从单质、氧化物、酸、碱、盐的类别寻找转化路径。",
        "每一根箭头都要有反应物、条件和产物证据。",
        "四种基本反应类型按反应物和生成物的种类与类别判断。",
        "四种基本反应类型不能包含所有化学反应。",
        "流程题逐箭头核对，最后用方程式和守恒校验。"
      ],
      "visualSummary": {
        "kind": "tree",
        "title": "物质转化与反应分类总树",
        "tree": {
          "label": "先判断能否反应",
          "children": [
            {
              "label": "写出每一步方程式",
              "children": [
                {
                  "label": "标条件与现象"
                }
              ]
            },
            {
              "label": "再按结构分类",
              "children": [
                {
                  "label": "多变一｜化合"
                },
                {
                  "label": "一变多｜分解"
                },
                {
                  "label": "单质+化合物｜置换"
                },
                {
                  "label": "化合物交换成分｜复分解"
                }
              ]
            },
            {
              "label": "用元素与原子守恒校验"
            }
          ]
        },
        "axes": [
          {
            "label": "金属通道",
            "items": [
              "金属单质",
              "金属氧化物",
              "碱",
              "盐"
            ]
          },
          {
            "label": "非金属通道",
            "items": [
              "非金属单质",
              "非金属氧化物",
              "酸",
              "盐"
            ]
          }
        ]
      },
      "rootTree": {
        "label": "解题主线",
        "rule": "不看最终答案倒猜；沿图逐箭头判断。",
        "examples": [
          "Ca→CaO→Ca(OH)₂→CaCO₃",
          "C→CO₂→H₂CO₃→CaCO₃"
        ],
        "visualSteps": [
          "判能否反应",
          "写方程式",
          "标条件",
          "按结构分类",
          "守恒校验"
        ],
        "children": [
          {
            "label": "第一关｜能否一步转化",
            "rule": "一步转化必须由一次化学反应完成，并满足反应条件。",
            "examples": [
              "MgCl₂加石灰乳得到Mg(OH)₂",
              "CuO不能直接与水生成Cu(OH)₂"
            ],
            "visualSteps": [
              "看反应物",
              "看条件",
              "看产物证据"
            ]
          },
          {
            "label": "第二关｜四种基本类型",
            "rule": "先数反应物和生成物的种类，再看单质、化合物类别。",
            "examples": [
              "CaO+H₂O=Ca(OH)₂｜化合",
              "Fe+CuSO₄=FeSO₄+Cu｜置换"
            ],
            "visualSteps": [
              "数种类",
              "认类别",
              "给名称"
            ]
          },
          {
            "label": "第三关｜流程与循环",
            "rule": "循环物质必须在前面消耗、后面重新生成，且每一步都能写出反应。",
            "examples": [
              "碳捕获流程",
              "钠及其化合物转化网络"
            ],
            "visualSteps": [
              "逐箭头",
              "找消耗",
              "找再生",
              "查守恒"
            ]
          }
        ]
      },
      "sections": [
        {
          "title": "常见物质转化关系与知识网络",
          "summary": "先搭两条主通道，再给每根箭头补证据。",
          "items": [
            {
              "label": "常见物质转化关系与知识网络",
              "rule": "从单质、氧化物、酸、碱、盐的类别出发寻找路径。金属常沿“金属单质→金属氧化物→碱→盐”转化，非金属常沿“非金属单质→非金属氧化物→酸→盐”转化；每一步都要写出反应物、条件和产物。",
              "examples": [
                "Ca→CaO→Ca(OH)₂→CaCO₃",
                "C→CO₂→H₂CO₃→CaCO₃"
              ],
              "visualSteps": [
                "定元素",
                "认物质类别",
                "连可行箭头",
                "补方程式与条件"
              ],
              "caution": "转化网络表示可能的反应路径，不表示所有相邻类别都一定能直接反应。"
            }
          ]
        },
        {
          "title": "一步转化的可行性与反应条件",
          "summary": "“能写箭头”之前先过反应条件关。",
          "items": [
            {
              "label": "一步转化的可行性与反应条件",
              "rule": "一步转化只能经过一次化学反应。先判断物质能否接触并反应，再检查点燃、加热、催化剂、过量或少量等条件；复分解反应通常要有沉淀、气体或弱电解质等推动。",
              "examples": [
                "MgCl₂→Mg(OH)₂→MgO：依次加石灰乳、再煅烧",
                "CuO难溶且不与水反应，不能一步得到Cu(OH)₂"
              ],
              "visualSteps": [
                "一次反应",
                "检查条件",
                "检查推动力",
                "核对产物"
              ],
              "caution": "CuO、Fe₂O₃、SiO₂等不能机械套用“氧化物+水”。"
            }
          ]
        },
        {
          "title": "化合、分解、置换、复分解反应",
          "summary": "用结构树判断，不靠关键词猜。",
          "items": [
            {
              "label": "化合、分解、置换、复分解反应",
              "rule": "化合反应是多种物质生成一种物质；分解反应是一种物质生成多种物质；置换反应是单质+化合物生成新单质+新化合物；复分解反应是两种化合物交换成分生成两种新化合物。",
              "examples": [
                "CaO+H₂O=Ca(OH)₂｜化合；加热条件下：CaCO₃=CaO+CO₂↑｜分解",
                "Fe+CuSO₄=FeSO₄+Cu｜置换；Na₂CO₃+2HCl=2NaCl+H₂O+CO₂↑｜复分解"
              ],
              "visualSteps": [
                "看反应物种类",
                "看生成物种类",
                "认单质/化合物",
                "按结构命名"
              ],
              "caution": "“氧化反应”“中和反应”不是四种基本反应类型中的名称。"
            }
          ]
        },
        {
          "title": "四种基本反应类型的边界与反例",
          "summary": "四种基本反应类型有清楚边界。",
          "items": [
            {
              "label": "四种基本反应类型的边界与反例",
              "rule": "四种基本反应类型不能包含所有反应。生成单质不等于一定是置换；两种化合物反应不等于一定是复分解；有盐和水生成也不等于一定是中和。",
              "examples": [
                "加热条件下：CO+CuO=Cu+CO₂；反应物中没有单质，不是置换",
                "CO₂+2NaOH=Na₂CO₃+H₂O；反应物没有两种化合物交换成分，不是复分解"
              ],
              "visualSteps": [
                "先看结构",
                "逐项对照定义",
                "找不满足条件",
                "给出边界结论"
              ],
              "caution": "同一反应可按不同标准命名；本卡只判断四种基本反应类型，不提前要求氧化还原知识。"
            }
          ]
        },
        {
          "title": "转化流程与反应分类综合",
          "summary": "流程图逐箭头拆开，每一步单独判断。",
          "items": [
            {
              "label": "转化流程与反应分类综合",
              "rule": "先确认每个节点的物质类别，再逐步写方程式、标条件和现象，最后给每一步分类。判断循环物质时，要同时看到它在前面被消耗、在后面被重新生成。",
              "examples": [
                "碳捕获：CO₂被NaOH吸收，再由CaCO₃高温分解释放CO₂",
                "钠及其化合物网络：逐箭头核对Na、Na₂O₂、NaOH、Na₂CO₃之间的反应"
              ],
              "visualSteps": [
                "认节点",
                "逐箭头写反应",
                "逐步分类",
                "找消耗与再生",
                "查元素和原子守恒"
              ],
              "caution": "同一物质在图中出现两次，不代表它一定能循环利用。"
            }
          ]
        }
      ],
      "workedExamples": [
        {
          "substance": "钙元素转化网络",
          "path": "点燃条件下：2Ca+O₂=2CaO；CaO+H₂O=Ca(OH)₂；Ca(OH)₂+CO₂=CaCO₃↓+H₂O。按箭头依次得到化合、化合、复分解。",
          "labels": [
            "逐箭头",
            "写条件",
            "再分类",
            "原子守恒"
          ]
        },
        {
          "substance": "边界判断：CO还原CuO",
          "path": "加热条件下：CO+CuO=Cu+CO₂。虽然生成Cu单质，但反应物中没有单质，不满足“单质+化合物”的置换结构，所以不属于置换反应。",
          "labels": [
            "看反应物类别",
            "不靠生成单质猜",
            "边界反例"
          ]
        }
      ],
      "checkpoints": [
        "我能画出金属和非金属两条常见转化通道。",
        "我会逐箭头写方程式并补反应条件。",
        "我能按结构区分化合、分解、置换和复分解反应。",
        "我知道四种基本反应类型不能包含所有反应。",
        "我会用元素、原子和反应条件校验流程。"
      ],
      "scopeNote": "覆盖苏教版必修第一册物质转化关系与四种基本反应类型；不把氧化还原判断设为前置要求。"
    },
    "concept_manifest": [
      {
        "id": "H1_REACTION_CLASSIFICATION__C01",
        "title": "常见物质转化关系与知识网络"
      },
      {
        "id": "H1_REACTION_CLASSIFICATION__C02",
        "title": "一步转化的可行性与反应条件"
      },
      {
        "id": "H1_REACTION_CLASSIFICATION__C03",
        "title": "化合、分解、置换、复分解反应"
      },
      {
        "id": "H1_REACTION_CLASSIFICATION__C04",
        "title": "四种基本反应类型的边界与反例"
      },
      {
        "id": "H1_REACTION_CLASSIFICATION__C05",
        "title": "转化流程与反应分类综合"
      }
    ]
  },
  {
    "id": "KC_H1_SOLUTION_CONCENTRATION_ZERO",
    "skill_id": "H1_SOLUTION_CONCENTRATION",
    "title": "先认最终溶液体积，再完成浓度、稀释、配制与误差判断",
    "core": "物质的量浓度题先认清溶质和最终溶液体积，再决定用定义式、稀释式、配制流程或c=n/V误差树。",
    "detail": "五个细知识点按定义、换算、稀释混合、配制和误差完整展开。",
    "steps": [
      "物质的量浓度概念、溶液体积与离子浓度",
      "物质的量浓度与质量分数、密度的换算",
      "稀释、混合与体积边界",
      "一定物质的量浓度溶液的配制",
      "配制操作的误差分析"
    ],
    "common_mistakes": [
      "把水的体积当最终溶液体积",
      "混合体积机械相加",
      "误差分析不先看n和V"
    ],
    "micro_example": "100 mL 5.00 mol·L^-1盐酸定容到1.00 L，所得浓度为0.500 mol·L^-1。",
    "asset": {
      "type": "structured_knowledge",
      "contractVersion": 4,
      "studentSourceHidden": true
    },
    "review_status": "approved",
    "structured_content": {
      "version": 4,
      "intro": "物质的量浓度题先认清溶质和最终溶液体积，再决定用定义式、稀释式、配制流程或c=n/V误差树。",
      "overview": [
        "定义式中的V是最终溶液体积，不是水的体积。",
        "质量分数换算先取1 L溶液，再按质量链计算。",
        "稀释只在同一溶质无损失时使用c₁V₁=c₂V₂。",
        "容量瓶按计算、转移、定容和摇匀的顺序使用。",
        "误差只追踪n和V：先判n，再判V，最后判c。"
      ],
      "visualSummary": {
        "kind": "flow",
        "title": "浓度题五步判断流程",
        "steps": [
          {
            "label": "认溶质与最终溶液体积",
            "caption": "01"
          },
          {
            "label": "求溶质物质的量n",
            "caption": "02"
          },
          {
            "label": "选择c=n/V或c₁V₁=c₂V₂",
            "caption": "03"
          },
          {
            "label": "按器材与条件完成配制",
            "caption": "04"
          },
          {
            "label": "用n/V变化校验误差",
            "caption": "05"
          }
        ]
      },
      "rootTree": {
        "label": "c=n/V",
        "rule": "先确认n和V分别指什么；V必须是最终溶液体积，单位换成L。",
        "examples": [
          "0.20 mol·L^-1 MgCl₂中c(Cl⁻)=0.40 mol·L^-1",
          "把溶质加入1 L水不等于得到1 L溶液"
        ],
        "visualSteps": [
          "认溶质",
          "求n",
          "认最终V",
          "相除",
          "查单位"
        ],
        "children": [
          {
            "label": "n改变",
            "rule": "溶质洒失、未完全转移或未洗涤，都会使实际n偏小。",
            "examples": [
              "转移时洒失→n偏小→c偏低",
              "容量瓶用待配溶液润洗→n偏大→c偏高"
            ],
            "visualSteps": [
              "看溶质是否损失",
              "判n↑/↓",
              "再判c"
            ]
          },
          {
            "label": "V改变",
            "rule": "定容仰视使V偏大，俯视使V偏小；摇匀后液面下降不能补水。",
            "examples": [
              "仰视→V偏大→c偏低",
              "俯视→V偏小→c偏高"
            ],
            "visualSteps": [
              "看液面",
              "判V↑/↓",
              "再判c"
            ]
          },
          {
            "label": "n、V都不变",
            "rule": "容量瓶内原有少量蒸馏水，后续仍定容到刻度线，通常不改变最终浓度。",
            "examples": [
              "容量瓶有少量水→n不变、最终V不变→c不变"
            ],
            "visualSteps": [
              "查n",
              "查最终V",
              "两者不变",
              "c不变"
            ]
          }
        ]
      },
      "sections": [
        {
          "title": "物质的量浓度概念、溶液体积与离子浓度",
          "summary": "定义、对象、体积和离子计量数必须同时看。",
          "items": [
            {
              "label": "物质的量浓度概念、溶液体积与离子浓度",
              "rule": "c(B)=n(B)/V(溶液)，常用单位mol·L^-1；V是最终溶液体积。均一溶液取出一部分时浓度不变；强电解质的离子浓度按电离方程式计量数换算，并检查电荷守恒。",
              "examples": [
                "0.20 mol·L^-1 MgCl₂中c(Mg²⁺)=0.20 mol·L^-1、c(Cl⁻)=0.40 mol·L^-1",
                "从均一溶液取10 mL，浓度不变，所取溶质的n随体积减小"
              ],
              "visualSteps": [
                "认B",
                "求n(B)",
                "认最终V",
                "算c(B)",
                "离子按系数换算"
              ],
              "caution": "1 L水不是1 L溶液；混合前液体体积也不能在题目未说明时机械相加。"
            }
          ]
        },
        {
          "title": "物质的量浓度与质量分数、密度的换算",
          "summary": "固定从1 L溶液出发，避免漏掉1000。",
          "items": [
            {
              "label": "物质的量浓度与质量分数、密度的换算",
              "rule": "同一溶液中c=1000ρw/M；ρ用g·cm^-3、M用g·mol^-1时，c的单位为mol·L^-1。推导顺序是1 L溶液→溶液质量→溶质质量→物质的量。",
              "examples": [
                "1 L溶液体积为1000 cm³，质量为1000ρ g",
                "溶质质量为1000ρw g，所以n=1000ρw/M mol"
              ],
              "visualSteps": [
                "取1 L溶液",
                "m(溶液)=1000ρ",
                "m(溶质)=1000ρw",
                "除以M",
                "得到c"
              ],
              "caution": "质量分数依赖质量，物质的量浓度依赖最终体积；两者不能直接比较。"
            }
          ]
        },
        {
          "title": "稀释、混合与体积边界",
          "summary": "先判断是否反应，再判断体积能否相加。",
          "items": [
            {
              "label": "稀释、混合与体积边界",
              "rule": "同一溶质只加水稀释且无损失时，c₁V₁=c₂V₂。混合同一溶质先加n，再除以混合后的总体积；不同溶液混合先判断是否反应，若反应则先按方程式处理n。",
              "examples": [
                "100 mL 5.00 mol·L^-1盐酸定容到1.00 L，c=0.500 mol·L^-1",
                "取稀释后的均一溶液5 mL，浓度仍为0.500 mol·L^-1"
              ],
              "visualSteps": [
                "是否同一溶质",
                "是否发生反应",
                "求总n",
                "确认最终V",
                "求c"
              ],
              "caution": "把10 mL溶液与90 mL水混合，最终体积不一定恰好100 mL。"
            }
          ]
        },
        {
          "title": "一定物质的量浓度溶液的配制",
          "summary": "固体配液和浓溶液稀释在前半程不同，后半程相同。",
          "items": [
            {
              "label": "一定物质的量浓度溶液的配制",
              "rule": "固体配液依次为计算、称量、溶解并冷却、转移、洗涤并转移洗液、定容、摇匀、装瓶贴签；浓溶液稀释把称量换成量取，并先在烧杯中稀释、冷却。",
              "examples": [
                "配制250 mL 0.100 mol·L^-1 NaCl溶液：先按0.250 L计算所需n",
                "定容到刻度线下1～2 cm时改用胶头滴管，视线与凹液面最低点相平"
              ],
              "visualSteps": [
                "计算",
                "称量/量取",
                "溶解/稀释并冷却",
                "转移洗涤",
                "定容摇匀"
              ],
              "caution": "容量瓶不能用来溶解、稀释放热、加热、反应或长期储存；480 mL等非规格体积按合适容量瓶的标定体积计算。"
            }
          ]
        },
        {
          "title": "配制操作的误差分析",
          "summary": "所有误差都回到c=n/V。",
          "items": [
            {
              "label": "配制操作的误差分析",
              "rule": "先判实际转入容量瓶的溶质物质的量n是否改变，再判定容后的实际体积V是否改变，最后由c=n/V判断偏高、偏低或不变。",
              "examples": [
                "未洗涤烧杯和玻璃棒→n偏小、V不变→c偏低",
                "未冷却就定容→冷却后V偏小、n不变→c偏高"
              ],
              "visualSteps": [
                "操作",
                "判n↑/↓/不变",
                "判V↑/↓/不变",
                "判c"
              ],
              "caution": "超过刻度线要重新配制；摇匀后液面下降不能补水。"
            }
          ]
        }
      ],
      "workedExamples": [
        {
          "substance": "盐酸稀释",
          "path": "取100 mL 5.00 mol·L^-1盐酸，加水定容到1.00 L。由c₁V₁=c₂V₂，c₂=0.500 mol·L^-1；再取任意一部分，浓度仍为0.500 mol·L^-1。",
          "labels": [
            "同一溶质",
            "无损失",
            "最终体积",
            "浓度均一"
          ]
        },
        {
          "substance": "配制NaCl溶液并判断误差",
          "path": "配制250 mL 0.100 mol·L^-1 NaCl溶液时，先算n=0.0250 mol，再称量、溶解冷却、转移洗涤、定容摇匀。若转移时洒失，则n偏小而V不变，c偏低。",
          "labels": [
            "先算n",
            "完整流程",
            "c=n/V",
            "洒失偏低"
          ]
        }
      ],
      "checkpoints": [
        "我能说明c=n/V中n和V的对象与单位。",
        "我会由ρ、w、M推导c=1000ρw/M。",
        "我会判断什么时候能用c₁V₁=c₂V₂。",
        "我能按顺序说出固体配液和浓溶液稀释步骤。",
        "我会沿n变化、V变化、c变化三步判断误差。"
      ],
      "scopeNote": "覆盖苏教版必修第一册溶液组成的定量研究；所有公式都明确对象、条件和单位。"
    },
    "concept_manifest": [
      {
        "id": "H1_SOLUTION_CONCENTRATION__C01",
        "title": "物质的量浓度概念、溶液体积与离子浓度"
      },
      {
        "id": "H1_SOLUTION_CONCENTRATION__C02",
        "title": "物质的量浓度与质量分数、密度的换算"
      },
      {
        "id": "H1_SOLUTION_CONCENTRATION__C03",
        "title": "稀释、混合与体积边界"
      },
      {
        "id": "H1_SOLUTION_CONCENTRATION__C04",
        "title": "一定物质的量浓度溶液的配制"
      },
      {
        "id": "H1_SOLUTION_CONCENTRATION__C05",
        "title": "配制操作的误差分析"
      }
    ]
  }
]$h1_opening_cards$::jsonb)
)
insert into public.chem_knowledge_cards (
  id, skill_id, title, core, detail, steps, common_mistakes, micro_example,
  asset, review_status, structured_content
)
select
  card->>'id',
  card->>'skill_id',
  card->>'title',
  card->>'core',
  card->>'detail',
  card->'steps',
  card->'common_mistakes',
  card->>'micro_example',
  card->'asset',
  card->>'review_status',
  card->'structured_content'
from reviewed_cards
on conflict (id) do update set
  skill_id = excluded.skill_id,
  title = excluded.title,
  core = excluded.core,
  detail = excluded.detail,
  steps = excluded.steps,
  common_mistakes = excluded.common_mistakes,
  micro_example = excluded.micro_example,
  asset = excluded.asset,
  review_status = excluded.review_status,
  structured_content = excluded.structured_content,
  updated_at = now();

do $h1_opening_contract$
begin
  if exists (
    select 1
    from public.chem_skills as skill
    where skill.id in ('H1_REACTION_CLASSIFICATION', 'H1_SOLUTION_CONCENTRATION')
      and (
        jsonb_typeof(skill.level_criteria) is distinct from 'array'
        or jsonb_array_length(skill.level_criteria) <> skill.max_level
        or exists (
          select 1
          from jsonb_array_elements(skill.level_criteria) with ordinality as criterion(value, ordinal)
          where case
              when coalesce(criterion.value->>'level', '') ~ '^[1-9][0-9]*$'
                then (criterion.value->>'level')::integer
              else -1
            end <> criterion.ordinal
            or length(btrim(coalesce(criterion.value->>'studentFacingGoal', ''))) = 0
            or length(btrim(coalesce(criterion.value->>'requiredAbility', ''))) = 0
        )
      )
  ) then
    raise exception 'H1 opening skill level criteria do not match the typed three-level contract';
  end if;

  if (
    select count(*)
    from public.chem_knowledge_cards
    where id in ('KC_H1_REACTION_CLASSIFICATION_ZERO', 'KC_H1_SOLUTION_CONCENTRATION_ZERO')
  ) <> 2 then
    raise exception 'H1 opening knowledge cards were not both stored';
  end if;

  if exists (
    select 1
    from public.chem_knowledge_cards
    where id in ('KC_H1_REACTION_CLASSIFICATION_ZERO', 'KC_H1_SOLUTION_CONCENTRATION_ZERO')
      and (
        review_status <> 'approved'
        or coalesce((structured_content->>'version')::integer, 0) <> 4
        or jsonb_array_length(coalesce(structured_content->'sections', '[]'::jsonb)) <> 5
        or jsonb_array_length(coalesce(structured_content->'workedExamples', '[]'::jsonb)) < 2
        or jsonb_array_length(coalesce(structured_content->'checkpoints', '[]'::jsonb)) <> 5
        or coalesce((asset->>'contractVersion')::integer, 0) <> 4
        or coalesce((asset->>'studentSourceHidden')::boolean, false) is not true
      )
  ) then
    raise exception 'H1 opening knowledge-card v4 contract failed';
  end if;

  if exists (
    select skill_id
    from public.chem_knowledge_cards
    where skill_id in ('H1_REACTION_CLASSIFICATION', 'H1_SOLUTION_CONCENTRATION')
      and review_status = 'approved'
    group by skill_id
    having count(*) <> 1
  ) then
    raise exception 'H1 opening skill has more than one approved knowledge card';
  end if;

  if exists (
    select expected.skill_id
    from (values
      ('H1_REACTION_CLASSIFICATION'),
      ('H1_SOLUTION_CONCENTRATION')
    ) as expected(skill_id)
    where not exists (
      select 1
      from public.chem_knowledge_cards card
      where card.skill_id = expected.skill_id and card.review_status = 'approved'
    )
  ) then
    raise exception 'H1 opening skill is missing its approved knowledge card';
  end if;
end;
$h1_opening_contract$;

commit;
