insert into public.chem_questions(id,mother_id,skill_id,level,grade_band,stem,options,correct_option,explanation,scaffold,review_status,scope_status,source_kind)
values
('Q_J_01','M_J_PARTICLE_1','J09_ATOM',1,'初三','保持氧气化学性质的最小微粒是？','["氧原子","氧分子","氧离子","电子"]',1,'氧气由氧分子构成，保持其化学性质的最小微粒是氧分子。',null,'approved','IN','teacher_original'),
('Q_J_02','M_J_ATOM_2','J09_ATOM',1,'初三','原子中一定带正电的微粒是？','["质子","中子","电子","原子核外电子层"]',0,'质子带正电，电子带负电，中子不带电。',null,'approved','IN','original_variant'),
('Q_J_03','M_J_NUMBER_3','J09_ATOM',2,'初三','某原子的质子数为8，核外电子数为8，该原子整体显？','["正电性","负电性","电中性","无法判断"]',2,'质子与电子所带电荷数相等，整体电中性。','比较正负电荷总数。','approved','IN','teacher_original'),
('Q_J_04','M_J_SYMBOL_4','J09_ATOM',2,'初三','元素符号 N 表示的元素是？','["氖","氮","钠","镍"]',1,'N 是氮元素的符号，氖为 Ne，钠为 Na。',null,'approved','IN','original_variant'),
('Q_J_05','M_J_NEUTRON_5','J09_ATOM',2,'初三','某原子的质量数为23、质子数为11，其中子数为？','["11","12","23","34"]',1,'中子数=质量数−质子数=23−11=12。','题目已给质量数，可直接相减。','approved','IN','teacher_original'),
('Q_H2_01','M_H2_RATE_1','H2_RATE',1,'高二','其他条件不变，升高温度通常会使化学反应速率？','["增大","减小","不变","先减后增"]',0,'升温使活化分子百分数增大，有效碰撞增多，反应速率通常增大。',null,'approved','IN','teacher_original'),
('Q_H2_02','M_H2_CATALYST_2','H2_RATE',1,'高二','催化剂能加快反应速率的主要原因是？','["增大反应热","降低活化能","增大平衡常数","增加反应物总量"]',1,'催化剂提供活化能较低的反应路径。',null,'approved','IN','original_variant'),
('Q_H2_03','M_H2_CONC_3','H2_RATE',2,'高二','恒温恒容下，增大气体反应物浓度，正反应速率瞬间通常？','["增大","减小","不变","变为零"]',0,'反应物浓度增大，有效碰撞频率增大，正反应速率增大。','先判断瞬间浓度变化。','approved','IN','teacher_original'),
('Q_H2_04','M_H2_LIMIT_4','H2_RATE',2,'高二','可逆反应达到化学平衡时，正确的是？','["反应停止","正逆反应速率相等","各物质浓度相等","反应物完全转化"]',1,'化学平衡是动态平衡，正逆反应速率相等但均不为零。',null,'approved','IN','teacher_original'),
('Q_H2_05','M_H2_PRESSURE_5','H2_RATE',2,'高二','对有气体参加的反应，恒温压缩容器通常使气体反应速率？','["增大","减小","不变","无法比较"]',0,'压缩使气体浓度增大，单位体积内有效碰撞增多。',null,'approved','IN','original_variant'),
('Q_H3_01','M_H3_STATE_1','H3_EQUILIBRIUM',1,'高三','一定条件下可逆反应达到平衡的本质标志是？','["各组分浓度相等","正逆反应速率相等","混合物质量不变","反应物不再消耗"]',1,'平衡状态的本质是正、逆反应速率相等。',null,'approved','IN','teacher_original'),
('Q_H3_02','M_H3_K_2','H3_EQUILIBRIUM',2,'高三','一定温度下，化学平衡常数 K 主要取决于？','["起始浓度","催化剂","温度","容器体积"]',2,'对确定反应，平衡常数只随温度变化。',null,'approved','IN','original_variant'),
('Q_H3_03','M_H3_CATALYST_3','H3_EQUILIBRIUM',2,'高三','向已达平衡的可逆反应中加入催化剂，平衡如何变化？','["正向移动","逆向移动","不移动","无法确定"]',2,'催化剂同等程度加快正逆反应，不改变平衡组成。',null,'approved','IN','teacher_original'),
('Q_H3_04','M_H3_QK_4','H3_EQUILIBRIUM',3,'高三','某反应在当前状态下 Q<K，反应将优先向哪个方向进行？','["正反应方向","逆反应方向","保持不变","先逆后正"]',0,'Q<K 时体系通过正向反应增大 Q，直至达到 K。','比较Q和K判断方向。','approved','IN','teacher_original'),
('Q_H3_05','M_H3_TEMP_5','H3_EQUILIBRIUM',3,'高三','对放热的正反应，升高温度后平衡通常？','["正向移动","逆向移动","不移动","K不变"]',1,'升温使平衡向吸热方向即逆反应方向移动，且K改变。',null,'approved','IN','original_variant')
on conflict(id) do update set stem=excluded.stem,options=excluded.options,correct_option=excluded.correct_option,explanation=excluded.explanation,scaffold=excluded.scaffold,review_status=excluded.review_status,scope_status=excluded.scope_status,updated_at=now();

insert into public.chem_knowledge_cards(id,skill_id,title,core,detail,steps,common_mistakes,micro_example,review_status)
values
('CARD_J_ATOM','J09_ATOM','原子结构：先看电荷，再看数量','质子带正电、电子带负电、中子不带电。','原子中质子数等于核外电子数时整体电中性；中子数必须由质量数减质子数得到。','["辨认微粒电性","比较质子数与电子数","题给质量数时再求中子数"]','["把相对原子质量当质量数","把元素符号相近的元素混淆"]','质量数23、质子数11，则中子数12。','approved'),
('CARD_H2_RATE','H2_RATE','速率与平衡：先分清瞬间和最终','浓度、压强、温度先改变速率；平衡移动还要继续比较正逆速率。','催化剂降低正逆反应活化能，只缩短达到平衡的时间，不改变平衡组成。','["判断条件如何改变","写出正逆速率瞬间变化","再判断是否形成新平衡"]','["把速率增大直接等同正向移动","认为平衡时反应停止"]','加催化剂：正逆速率均增大，平衡不移动。','approved'),
('CARD_H3_EQ','H3_EQUILIBRIUM','平衡综合：状态、方向、限度分开','v正=v逆判断状态；Q与K判断方向；K描述温度一定时的限度。','催化剂不改变K；改变温度会改变K；浓度和压强改变Q，进而影响移动方向。','["先固定反应与温度","写Q或K表达式","比较Q与K","检查新平衡"]','["把浓度相等当平衡","忽略温度对K的影响"]','Q<K时反应正向进行，直到Q=K。','approved')
on conflict(id) do update set title=excluded.title,core=excluded.core,detail=excluded.detail,steps=excluded.steps,common_mistakes=excluded.common_mistakes,micro_example=excluded.micro_example,review_status=excluded.review_status,updated_at=now();
