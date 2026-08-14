const rawHigh1ReviewQuestionBank = {
  H1_CLASSIFY: [
    ['空气由多种气体组成，属于混合物。', true, '空气中含N₂、O₂、稀有气体等多种物质，应按混合物判断。'],
    ['冰水共存物只含H₂O一种物质，属于纯净物。', true, '同一种物质的不同状态共存，不会因此变成混合物。'],
    ['O₂和O₃组成的气体只含氧元素，所以属于纯净物。', false, 'O₂和O₃是两种不同单质，混在一起仍是混合物。'],
    ['由一种元素组成的纯净物一定是单质。', true, '先满足纯净物，再满足只含一种元素，才可判为单质。'],
    ['Na₂O属于碱性氧化物。', true, 'Na₂O能与酸反应生成盐和水，也能与水生成NaOH。'],
    ['CO₂属于酸性氧化物。', true, 'CO₂能与碱反应生成盐和水，是典型酸性氧化物。'],
    ['CO属于酸性氧化物。', false, 'CO通常既不与酸反应生成盐和水，也不与碱反应生成盐和水，属于不成盐氧化物。'],
    ['Al₂O₃只能归为碱性氧化物。', false, 'Al₂O₃既能与酸反应，也能与强碱反应，属于两性氧化物。'],
    ['H₂SO₄按可电离出的H⁺数目可归为二元酸。', true, '每个H₂SO₄分子可分步电离出两个H⁺。'],
    ['H₃PO₄按可电离出的H⁺数目可归为三元酸。', true, 'H₃PO₄可分步电离出三个H⁺，酸的元数不等于电离强弱。'],
    ['NaHSO₄的化学式中含H，因此NaHSO₄属于酸。', false, 'NaHSO₄由Na⁺和HSO₄⁻构成，按组成属于酸式盐。'],
    ['Ba(OH)₂按每个化学式单位中OH⁻数目可归为二元碱。', true, 'Ba(OH)₂完全电离时每个化学式单位给出两个OH⁻。'],
    ['Cu(OH)₂含有OH⁻，所以一定是强碱。', false, '碱的强弱看电离程度，Cu(OH)₂是难溶弱碱。'],
    ['溶液的分散质粒子直径通常小于1 nm。', true, '溶液中分散质以分子或离子尺度均匀分散，粒子直径通常小于1 nm。'],
    ['悬浊液的分散质粒子直径通常小于1 nm。', false, '悬浊液的分散质粒子通常大于100 nm，静置时容易沉降。'],
    ['丁达尔效应可用于区分胶体与溶液。', true, '胶体粒子能使光发生明显散射，形成可见光路。'],
    ['HCl在水溶液中能自身电离产生自由离子，HCl属于电解质。', true, '判断对象是HCl这种化合物，不是盐酸这一混合物。'],
    ['铜能导电，所以铜属于电解质。', false, '电解质与非电解质只针对化合物；铜是单质，不能这样分类。'],
    ['蔗糖在水溶液中以分子存在，属于非电解质。', true, '蔗糖是化合物，但在水中和熔融状态下不能自身电离。'],
    ['SO₂溶于水后形成的体系能导电，因此SO₂属于电解质。', false, 'SO₂与水反应形成的体系会产生离子，但SO₂物质本身不发生电离，所以SO₂仍属于非电解质。'],
    ['NaCl溶液中只有NaCl一种物质，因此属于纯净物。', false, 'NaCl溶液至少含水和NaCl，按组成属于混合物。'],
    ['分散质粒子直径约为1～100 nm的分散系属于胶体。', true, '胶体按分散质粒子尺度判断，不按是否透明判断。'],
    ['可用普通滤纸把NaCl从NaCl溶液中直接过滤出来。', false, '溶液中的离子能通过普通滤纸，过滤不能分离溶质和溶剂。'],
    ['熔融NaCl中存在可自由移动的离子，NaCl属于电解质。', true, 'NaCl是化合物，在熔融状态能电离出可移动的Na⁺和Cl⁻。'],
    ['Na₂O由两种元素组成且其中一种是氧元素，所以先判为氧化物，再判为碱性氧化物。', true, '应先沿组成树确定氧化物，再根据与酸碱反应的性质细分。'],
  ],

  H1_GAS_MOLAR_VOLUME: [
    ['0 ℃、101 kPa属于高中常用的标准状况。', true, '标准状况的温度和压强必须同时满足，不能只看其中一个条件。'],
    ['任何温度和压强下，气体摩尔体积都等于22.4 L·mol⁻¹。', false, '气体摩尔体积随温度和压强改变，22.4 L·mol⁻¹只用于标准状况的常用近似。'],
    ['标准状况下，1 mol任何物质的体积都约为22.4 L。', false, '22.4 L·mol⁻¹只适用于标准状况下的气体，不适用于固体或液体。'],
    ['标准状况下的H₂O是液体，不能用22.4 L·mol⁻¹计算1 mol水的体积。', true, '使用气体摩尔体积前必须先判断物态。'],
    ['标准状况下0.25 mol N₂的体积约为5.6 L。', true, 'V=nVₘ=0.25×22.4 L=5.6 L。'],
    ['标准状况下33.6 L O₂的物质的量约为1.5 mol。', true, 'n=V/Vₘ=33.6/22.4 mol=1.5 mol。'],
    ['标准状况下4.48 L CO₂的物质的量约为0.20 mol。', true, '4.48÷22.4=0.20，体积单位与Vₘ匹配。'],
    ['标准状况下2 mol H₂的体积约为22.4 L。', false, '2 mol气体的体积约为2×22.4 L=44.8 L。'],
    ['标准状况下11.2 L N₂含有约0.5N_A个N₂分子。', true, '11.2 L对应0.5 mol N₂，因此分子数为0.5N_A。'],
    ['标准状况下11.2 L N₂含有约0.5N_A个N原子。', false, '0.5 mol N₂含1.0 mol N原子，即约N_A个N原子。'],
    ['标准状况下5.6 L CH₄含有约0.25N_A个CH₄分子。', true, '5.6 L对应0.25 mol CH₄，分子数为0.25N_A。'],
    ['标准状况下5.6 L CH₄含有约N_A个H原子。', true, '0.25 mol CH₄含1.0 mol H原子，所以H原子数约为N_A。'],
    ['标准状况下22.4 L CO₂的质量约为44 g。', true, '22.4 L CO₂约为1 mol，质量为1 mol×44 g·mol⁻¹。'],
    ['标准状况下11.2 L O₂的质量约为32 g。', false, '11.2 L O₂为0.5 mol，质量应为0.5×32 g=16 g。'],
    ['标准状况下5.6 L N₂的质量约为7.0 g。', true, '5.6 L N₂为0.25 mol，质量为0.25×28 g=7.0 g。'],
    ['标准状况下3.01×10²³个H₂分子的体积约为11.2 L。', true, '该分子数约为0.5 mol，再由V=nVₘ得到11.2 L。'],
    ['标准状况下44.8 L O₂的质量约为64 g。', true, '44.8 L O₂约为2 mol，质量为2×32 g=64 g。'],
    ['标准状况下22.4 L He的质量约为4.0 g。', true, '22.4 L He约为1 mol，质量约为4.0 g。'],
    ['同温同压下，等物质的量的不同气体体积相等。', true, '同温同压时不同气体的气体摩尔体积相同。'],
    ['同温同压下，两种气体的体积比等于其物质的量之比。', true, '由V=nVₘ且两者Vₘ相同，可得V₁/V₂=n₁/n₂。'],
    ['某条件下题目给出Vₘ=24.0 L·mol⁻¹，则0.50 mol气体体积为12.0 L。', true, '非标准状况应使用题给Vₘ，V=0.50×24.0 L。'],
    ['25 ℃、101 kPa下计算气体体积时，可不看题给条件直接使用22.4 L·mol⁻¹。', false, '25 ℃不是标准状况，不能机械套用22.4 L·mol⁻¹。'],
    ['标准状况下0.50 mol N₂与0.50 mol O₂混合后的总体积约为22.4 L。', true, '混合前后总物质的量为1.00 mol，同一条件下总体积约22.4 L。'],
    ['同温同压下，等体积H₂和O₂的质量相等。', false, '等体积对应等物质的量，但O₂的摩尔质量大于H₂，所以质量不相等。'],
    ['同温同压下，1.0 L H₂和1.0 L O₂所含分子数相等。', true, '同温同压下等体积气体含有相同物质的量，分子数也相等。'],
  ],

  H1_MOLE_INTRO: [
    ['1 mol指定微粒所含的微粒数约为6.02×10²³。', true, '1 mol任何指定微粒都含约N_A个该微粒。'],
    ['阿伏加德罗常数的单位可写为mol⁻¹。', true, 'N_A表示每摩尔所含微粒数，常用单位为mol⁻¹。'],
    ['1 mol O₂含有N_A个O原子。', false, '1 mol O₂含N_A个O₂分子，每个分子含2个O原子，共2N_A个O原子。'],
    ['0.50 mol H₂O含有约0.50N_A个H₂O分子。', true, '分子数N=nN_A=0.50N_A。'],
    ['0.50 mol H₂O含有约1.50N_A个原子。', true, '每个H₂O分子含3个原子，总原子数为0.50×3N_A。'],
    ['3.01×10²³个CO₂分子约为0.50 mol CO₂。', true, '该分子数约为N_A的一半，对应0.50 mol。'],
    ['1.204×10²⁴个N₂分子约为1 mol N₂。', false, '该数约为2N_A，对应2 mol N₂。'],
    ['O₂的摩尔质量为32 g。', false, '摩尔质量应带单位，O₂的摩尔质量为32 g·mol⁻¹。'],
    ['数值上，某物质的相对分子质量与其摩尔质量以g·mol⁻¹为单位时相等。', true, '二者物理意义和单位不同，但数值可对应。'],
    ['18 g H₂O的物质的量为1.0 mol。', true, 'n=m/M=18 g÷18 g·mol⁻¹=1.0 mol。'],
    ['9.0 g H₂O含有1 mol H₂O分子。', false, '9.0 g H₂O为0.50 mol，只含0.50N_A个H₂O分子。'],
    ['44 g CO₂的物质的量为1.0 mol。', true, 'CO₂的摩尔质量为44 g·mol⁻¹。'],
    ['11 g CO₂含有约0.25N_A个CO₂分子。', true, '11 g÷44 g·mol⁻¹=0.25 mol，分子数为0.25N_A。'],
    ['16 g O₂的物质的量为1.0 mol。', false, 'O₂的摩尔质量为32 g·mol⁻¹，16 g对应0.50 mol。'],
    ['14 g N₂含有约0.50N_A个N₂分子。', true, '14 g÷28 g·mol⁻¹=0.50 mol。'],
    ['23 g Na含有约N_A个Na原子。', true, 'Na的摩尔质量约为23 g·mol⁻¹，23 g为1 mol。'],
    ['0.25 mol NaCl含有约0.25N_A个NaCl化学式单位。', true, '离子晶体用化学式单位计数，仍满足N=nN_A。'],
    ['1 mol Na₂SO₄中所含原子总数约为6N_A。', false, '一个Na₂SO₄化学式单位含2+1+4=7个原子，总数为7N_A。'],
    ['0.20 mol CaCO₃中含有约0.60N_A个O原子。', true, '每个CaCO₃含3个O原子，0.20×3=0.60 mol O原子。'],
    ['等质量的O₂和CO₂所含分子数相等。', false, '等质量时物质的量与摩尔质量成反比，O₂的摩尔质量更小，分子数更多。'],
    ['等物质的量的CO₂和N₂所含分子数相等。', true, '指定微粒相同时，微粒数只由物质的量决定。'],
    ['1 mol电子所含电子数约为N_A。', true, '电子也可作为指定微粒使用物质的量计数。'],
    ['由微粒数求物质的量可用n=N/N_A。', true, 'N与n之间通过阿伏加德罗常数换算。'],
    ['0.10 mol Al₂(SO₄)₃含有0.30 mol SO₄²⁻。', true, '每个Al₂(SO₄)₃化学式单位含3个SO₄²⁻，对应物质的量为0.10×3 mol。'],
    ['1 mol NaCl所数对象应写为NaCl化学式单位，而不是NaCl分子。', true, 'NaCl是离子晶体，不存在独立NaCl分子，计数对象应为化学式单位。'],
  ],

  H1_PERIODIC: [
    ['主族元素的周期序数通常等于其原子的电子层数。', true, '周期反映原子核外电子层数。'],
    ['同周期主族元素从左到右，原子半径总体逐渐增大。', false, '核电荷数增加而电子层数相同，原子半径总体减小。'],
    ['第三周期中Na原子半径大于Mg原子半径。', true, '同周期从左到右原子半径总体减小。'],
    ['第三周期中Cl的非金属性强于S。', true, '同周期从左到右非金属性总体增强。'],
    ['同主族从上到下，原子半径总体增大。', true, '电子层数增加是半径增大的主要因素。'],
    ['同主族从上到下，元素的金属性总体减弱。', false, '原子更易失电子，金属性总体增强。'],
    ['Na的金属性强于K。', false, '同主族向下金属性增强，因此K强于Na。'],
    ['F的非金属性强于Cl。', true, '卤族从上到下非金属性减弱。'],
    ['NaOH的碱性强于Mg(OH)₂。', true, '第三周期最高价氧化物对应水化物的碱性从左到右总体减弱。'],
    ['HClO₄的酸性强于H₂SO₄。', true, '第三周期最高价含氧酸的酸性从左到右总体增强。'],
    ['同主族从上到下，气态氢化物的热稳定性总体增强。', false, '元素非金属性减弱、E—H键通常变弱，热稳定性总体下降。'],
    ['HF的热稳定性强于HCl。', true, 'F—H键强于Cl—H键，卤化氢热稳定性向下总体降低。'],
    ['所有主族元素的最高正化合价都等于其主族序数。', false, 'O、F等元素存在常见例外，不能机械套用。'],
    ['元素性质随原子序数递增呈周期性变化。', true, '核外电子排布的周期性导致性质的周期性。'],
    ['同主族元素的化学性质完全相同。', false, '价电子结构相似使性质相似，但原子半径等不同会造成差异。'],
    ['所有稀有气体原子的最外层都有8个电子。', false, 'He的最外层只有2个电子，已达到稳定结构。'],
    ['Na⁺的半径小于Na原子的半径。', true, 'Na失去最外层电子后电子层数减少，半径明显变小。'],
    ['Cl⁻的半径小于Cl原子的半径。', false, 'Cl得到电子后电子间排斥增强，阴离子半径大于相应原子。'],
    ['O²⁻、F⁻、Na⁺、Mg²⁺核外电子数相同，其中O²⁻半径最大。', true, '等电子粒子中核电荷数越小，对电子吸引越弱，半径越大。'],
    ['元素金属性越强，其原子通常越容易失去电子。', true, '金属性可从原子失电子能力理解。'],
    ['元素非金属性越强，其原子通常越容易得到电子。', true, '非金属性可从原子得电子能力理解。'],
    ['第三周期最高价氧化物对应水化物的酸性总体从左到右增强。', true, '随中心元素非金属性增强，最高价含氧酸酸性总体增强。'],
    ['第ⅦA族气态氢化物的热稳定性从HF到HI总体降低。', true, '向下原子半径增大，H—X键能总体降低。'],
    ['S²⁻、Cl⁻、K⁺、Ca²⁺核外电子数相同，其中Ca²⁺半径最大。', false, '这些粒子核外都有18个电子，核电荷数越大半径越小，因此S²⁻最大、Ca²⁺最小。'],
    ['Mg²⁺的半径大于Mg原子的半径。', false, 'Mg失去最外层两个电子形成Mg²⁺后电子层数减少，半径变小。'],
  ],

  H1_REDOX: [
    ['有元素化合价发生变化的反应属于氧化还原反应。', true, '化合价变化是高中判断氧化还原反应的直接标志。'],
    ['某元素化合价升高，表示该元素得到电子。', false, '化合价升高对应失去电子，发生氧化反应。'],
    ['某元素化合价降低，表示该元素得到电子。', true, '得到电子使有效正价降低，发生还原反应。'],
    ['氧化剂在反应中自身被还原。', true, '氧化剂得到电子、所含元素化合价降低。'],
    ['还原剂在反应中自身被还原。', false, '还原剂失去电子、自身被氧化。'],
    ['同一氧化还原反应中，氧化过程和还原过程必然同时发生。', true, '电子有失必有得，两个过程不可分开。'],
    ['单质中元素的化合价一定为0。', true, '未化合单质中各元素按0价处理。'],
    ['单原子离子的化合价在数值和符号上等于其所带电荷。', true, '如Fe³⁺中Fe为+3价，Cl⁻中Cl为−1价。'],
    ['H₂O₂中O元素的化合价为−2价。', false, '过氧化物H₂O₂中O元素为−1价。'],
    ['Cl₂+2OH⁻=Cl⁻+ClO⁻+H₂O中Cl₂只作氧化剂。', false, 'Cl由0价同时降到−1价、升到+1价，Cl₂既作氧化剂又作还原剂。'],
    ['同一种元素的不同价态生成中间价态的反应可能是归中反应。', true, '高、低价态相互靠近形成中间价态，体现电子转移。'],
    ['Fe²⁺转化为Fe³⁺时，每个Fe²⁺失去1个电子。', true, 'Fe由+2价升到+3价，失去1e⁻。'],
    ['MnO₄⁻中Mn元素的化合价为+7价。', true, '设Mn为x，有x+4×(−2)=−1，得x=+7。'],
    ['SO₃²⁻中S元素的化合价为+6价。', false, '设S为x，有x+3×(−2)=−2，得x=+4。'],
    ['H₂O₂只能表现氧化性，不能表现还原性。', false, 'H₂O₂中O为中间价态，遇不同反应物可表现氧化性或还原性。'],
    ['2Na+Cl₂=2NaCl中Na是还原剂。', true, 'Na由0价升到+1价，失电子并还原Cl₂。'],
    ['CuO+H₂=Cu+H₂O中CuO是氧化剂。', true, 'Cu由+2价降到0价，CuO得到电子并氧化H₂。'],
    ['HCl+NaOH=NaCl+H₂O属于氧化还原反应。', false, '各元素反应前后化合价不变，这是酸碱中和反应。'],
    ['AgNO₃+NaCl=AgCl↓+NaNO₃属于氧化还原反应。', false, '反应只发生离子交换和沉淀生成，没有化合价变化。'],
    ['配平氧化还原反应时，电子得失总数必须相等。', true, '电子守恒是确定氧化剂、还原剂计量关系的核心约束。'],
    ['电子守恒成立后，不必再检查原子守恒。', false, '配平还必须同时满足各元素原子数守恒，离子方程式还需满足电荷守恒。'],
    ['还原剂失电子后形成的物质称为氧化产物。', true, '还原剂发生氧化，其生成物是氧化产物。'],
    ['没有氧元素参加的反应一定不是氧化还原反应。', false, '氧化还原的本质是电子转移，如H₂与Cl₂反应不含氧仍是氧化还原。'],
    ['只要反应物中含有O₂，该反应就一定是氧化还原反应。', false, '仍应检查化合价是否变化，不能只凭物质中含氧作判断。'],
    ['2KClO₃=2KCl+3O₂↑中，Cl由+5价降为−1价，O由−2价升为0价。', true, 'Cl得到电子、O失去电子，反应中同时存在化合价升高和降低。'],
  ],
};

const comboOptions = ['Ⅰ、Ⅱ均正确', 'Ⅰ正确、Ⅱ错误', 'Ⅰ错误、Ⅱ正确', 'Ⅰ、Ⅱ均错误'];

const high1ConceptPlan = {
  H1_CLASSIFY: {
    matter_composition: [1, 2, 3, 4, 21],
    oxide_classification: [5, 6, 7, 8, 25],
    acid_base_salt_classification: [9, 10, 11, 12, 13],
    electrolyte_classification: [17, 18, 19, 20, 24],
    dispersion_system: [14, 15, 16, 22, 23],
  },
  H1_GAS_MOLAR_VOLUME: {
    standard_condition_scope: [1, 2, 3, 4, 22],
    amount_volume_conversion: [5, 6, 7, 8, 21],
    particle_volume_conversion: [9, 10, 11, 12, 16],
    mass_volume_conversion: [13, 14, 15, 17, 18],
    same_temperature_pressure_relation: [19, 20, 23, 24, 25],
  },
  H1_MOLE_INTRO: {
    amount_to_particle_count: [1, 3, 4, 5, 21],
    avogadro_constant_conversion: [2, 6, 7, 22, 23],
    molar_mass_and_amount: [8, 9, 10, 12, 14],
    mass_to_particle_count: [11, 13, 15, 16, 20],
    formula_unit_composition: [17, 18, 19, 24, 25],
  },
  H1_PERIODIC: {
    periodic_structure: [1, 13, 14, 15, 16],
    same_period_trend: [2, 3, 4, 20, 21],
    same_group_trend: [5, 6, 7, 8, 23],
    compound_property_trend: [9, 10, 11, 12, 22],
    particle_radius: [17, 18, 19, 24, 25],
  },
  H1_REDOX: {
    redox_identification: [1, 18, 19, 23, 24],
    electron_and_reagent_roles: [2, 3, 4, 5, 22],
    oxidation_number: [7, 8, 9, 13, 14],
    reagent_judgement_in_reaction: [10, 11, 15, 16, 17],
    electron_conservation: [6, 12, 20, 21, 25],
  },
};

const attachConcepts = (rawBank, plan) => Object.fromEntries(Object.entries(rawBank).map(([skillId, entries]) => {
  const groups = plan[skillId];
  if (!groups || Object.keys(groups).length !== 5) throw new Error(`${skillId} must define five concepts`);
  const assigned = new Map();
  for (const [conceptName, indices] of Object.entries(groups)) {
    if (indices.length !== 5) throw new Error(`${skillId}__${conceptName} must contain five variants`);
    indices.forEach((oneBasedIndex, groupIndex) => {
      if (assigned.has(oneBasedIndex)) throw new Error(`${skillId} item ${oneBasedIndex} is assigned twice`);
      assigned.set(oneBasedIndex, { conceptKey: `${skillId}__${conceptName}`, format: groupIndex < 2 ? 'combo' : 'tf' });
    });
  }
  if (assigned.size !== entries.length) throw new Error(`${skillId} concept plan does not cover all questions`);

  return [skillId, entries.map(([statement, truth, reason], index) => {
    const assignment = assigned.get(index + 1);
    if (!assignment) throw new Error(`${skillId} item ${index + 1} has no concept`);
    if (assignment.format === 'combo') {
      return {
        concept_key: assignment.conceptKey,
        format: 'combo',
        statement: `判断下列两项：Ⅰ.${statement} Ⅱ.${reason}`,
        options: comboOptions,
        correct_option: truth ? 'A' : 'C',
        explanation: `Ⅰ${truth ? '正确' : '错误'}，Ⅱ正确。${reason}`,
      };
    }
    return {
      concept_key: assignment.conceptKey,
      format: 'tf',
      statement,
      options: ['正确', '错误'],
      correct_option: truth ? 'A' : 'B',
      explanation: reason,
    };
  })];
}));

export const high1ReviewQuestionBank = attachConcepts(rawHigh1ReviewQuestionBank, high1ConceptPlan);
