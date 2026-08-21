-- Replace only the 34 source-checked H1/H2 student explanations.
--
-- Active/retired licensed_local rows are immutable. Therefore this migration
-- never updates an active question. It clones each complete active grade
-- release into a new staged generation, keeps all source images byte-identical,
-- assigns new question/asset paths and revision tokens, applies the audited
-- explanation text, recomputes the private ledger and manifest, and activates
-- the full release atomically. The former release remains retired for rollback.
-- H3, attempts, plans, quiz_sessions, and the independent quiz site are not touched.

begin;

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('chem-source-original-release', 0)
);
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('chem-h3-original-release', 0)
);

create temporary table _explanation_release_spec (
  grade_band text primary key,
  old_release_id uuid not null unique,
  old_manifest_sha256 text not null,
  new_release_id uuid not null unique,
  new_manifest_sha256 text not null unique,
  expected_question_count integer not null
) on commit drop;

insert into _explanation_release_spec(
  grade_band, old_release_id, old_manifest_sha256,
  new_release_id, new_manifest_sha256, expected_question_count
) values
('高一','9a156d70-a020-558f-8530-97ba3c6f21f8'::uuid,'c838e3ed51e396cbeeec268d01edb3c18b851129470f8fc3171c4ea54ff8d189','7082837f-1077-5656-b473-b51a4417aec9'::uuid,'ba88ba506e987b68ac836473e3b8059d29180173099dd5723871768fba0b1d8b',125),
('高二','8112ccbf-bc0d-58e9-9413-bb780c4eca2d'::uuid,'b0bee4fcfeab8d9d09a69b39c6b75924e19b8ee1e82da7d55e6285e3e0cf6f26','6ee2bee4-e0b8-53aa-aeb1-062ae673aaa3'::uuid,'1daf8be2966755f76a2b290cedd2c1fee1652e4c397987fb715a9cf2acf67edf',200);

create temporary table _explanation_overrides (
  canonical_source_id text primary key,
  source_manifest_id text not null unique,
  grade_band text not null,
  skill_id text not null,
  correct_option smallint not null,
  analysis_asset_sha256 text not null,
  is_combination boolean not null,
  explanation text not null
) on commit drop;

insert into _explanation_overrides(
  canonical_source_id, source_manifest_id, grade_band, skill_id,
  correct_option, analysis_asset_sha256, is_combination, explanation
) values
('--:H1_CLASSIFY-1b9a4961e19f9ef1','H1_CLASSIFY-1b9a4961e19f9ef1','高一','H1_CLASSIFY',3,'8d1e3db4f0dc7e2c8396a199deb7e1afce0fd041f0d8446810ee94795324c60d',false,$exp01$A．氧化物必须只由两种元素组成，且其中一种是氧元素。NH₄Cl含N、H、Cl三种元素且不含O，不属于氧化物，A错误。
B．酸在水溶液中电离出的阳离子全部是H⁺。NH₄Cl电离出的阳离子是NH₄⁺，不属于酸，B错误。
C．碱在水溶液中电离出的阴离子全部是OH⁻。NH₄Cl不能电离出OH⁻，不属于碱，C错误。
D．盐由金属阳离子或NH₄⁺与酸根阴离子构成。NH₄Cl由NH₄⁺和Cl⁻构成，属于盐，D正确。
故选D。$exp01$),
('--:H1_CLASSIFY-d4444004e516b6d9','H1_CLASSIFY-d4444004e516b6d9','高一','H1_CLASSIFY',0,'7c1d2454ce1ae4d005b1a2780ddf0df6ebc86edc058c6860ece46f8edf8ca29a',false,$exp02$A．所列成分中没有酸：铝粉是单质，NaOH是碱，NaClO和Na₂CO₃都是盐，因此A正确。
B．NaClO和Na₂CO₃都属于盐，所列成分包括盐，B错误。
C．铝粉是由铝元素组成的单质，所列成分包括单质，C错误。
D．NaOH属于碱，所列成分包括碱，D错误。
故选A。$exp02$),
('--:H1_CLASSIFY-9c10d205d0c4ea53','H1_CLASSIFY-9c10d205d0c4ea53','高一','H1_CLASSIFY',1,'382671ccb2c4a5d6b4e6b374f9eb202d3ec37c3aa921b7f2f84a6e7498277e27',false,$exp03$A．绿矾FeSO₄·7H₂O是具有固定组成的结晶水合物，属于纯净物，不属于混合物，A错误。
B．绿矾由Fe²⁺和SO₄²⁻等微粒构成，属于盐，B正确。
C．绿矾在水中电离出的阳离子不是全部为H⁺，不属于酸，C错误。
D．氧化物只含两种元素且其中一种是O。绿矾含Fe、S、O、H四种元素，不属于氧化物，D错误。
故选B。$exp03$),
('--:H1_CLASSIFY-c34ece625186af9b','H1_CLASSIFY-c34ece625186af9b','高一','H1_CLASSIFY',3,'3af04d47151d2cb3790e3a711098ba86f26e33157ef5d5793b67be4432857aa1',false,$exp04$A．金属氧化物不一定是碱性氧化物，例如Al₂O₃是两性氧化物，Mn₂O₇是酸性氧化物，A错误。
B．非金属氧化物不一定是酸性氧化物，例如CO、NO属于不成盐氧化物，B错误。
C．同素异形体是同种元素形成的不同单质，例如O₂和O₃；H₂O和H₂O₂都是化合物，不互为同素异形体，C错误。
D．盐可按阳离子和阴离子从不同角度交叉分类。NaNO₃既是钠盐，又是硝酸盐，D正确。
故选D。$exp04$),
('--:H1_CLASSIFY-29c7d725e1f6c199','H1_CLASSIFY-29c7d725e1f6c199','高一','H1_CLASSIFY',3,'a2f5fed0035d4fa32fb4783faeeb0a24784ca6cdd406a3ba3e8132414c6bb91d',false,$exp05$A．HNO₃在水中电离出的阳离子全部是H⁺，属于酸，A正确。
B．Ca(OH)₂在水中电离出的阴离子全部是OH⁻，属于碱，B正确。
C．CO₂能与碱反应生成盐和水，属于酸性氧化物，C正确。
D．液氯是液态Cl₂，只含一种物质，属于纯净物，不是混合物，D错误。
故选D。$exp05$),
('--:H1_CLASSIFY-b302795604e46db5','H1_CLASSIFY-b302795604e46db5','高一','H1_CLASSIFY',1,'6ae42c8548f589dc590508b11bd5d41aa3ae8b106cf68f03cd6690d7b15fca20',false,$exp06$A．空气由多种物质组成，是混合物，不属于纯净物，因此A错误。
B．Na₂CO₃·10H₂O是组成固定的纯净物；NaOH是电解质；CO₂是酸性氧化物；Na₂O是碱性氧化物，各项分类都正确，B正确。
C．汽油是多种烃组成的混合物；碱石灰是NaOH和CaO等组成的混合物；CO是不成盐氧化物，不是酸性氧化物，C错误。
D．食盐是混合物；Al是单质，既不是电解质也不是非电解质；Na₂O₂是过氧化物，不属于碱性氧化物，D错误。
故选B。$exp06$),
('--:H1_CLASSIFY-8b07da3704075665','H1_CLASSIFY-8b07da3704075665','高一','H1_CLASSIFY',0,'3560bde6c25b381b3578c90dfa946ba34b8cd11e74872b821d3ad06db34ee66a',false,$exp07$A．烧碱NaOH是纯净物，碘酒是混合物，Fe₂O₃是碱性氧化物，SiO₂是酸性氧化物，分类均正确，A正确。
B．冰水混合物只含H₂O，属于纯净物，不是混合物，B错误。
C．熟石灰Ca(OH)₂是纯净物；Na₂O₂是过氧化物，不属于碱性氧化物，C错误。
D．石灰石是混合物，胆矾CuSO₄·5H₂O是组成固定的纯净物，D错误。
故选A。$exp07$),
('--:H1_CLASSIFY-600fea98209ad70e','H1_CLASSIFY-600fea98209ad70e','高一','H1_CLASSIFY',1,'2383fefb16ff5ff383c15dee482f7a5ae24316e1a9439ad700dcdb98a6f2b14d',false,$exp08$A．盐酸是HCl的水溶液，属于混合物；Na₂O₂是过氧化物，不是碱性氧化物；CO是不成盐氧化物，不是酸性氧化物，A错误。
B．HClO是酸，Ba(OH)₂是碱，Fe₂S₃是盐，NH₃·H₂O是纯净物，石灰石是混合物，Na₂O是碱性氧化物，SO₂是酸性氧化物，分类均正确，B正确。
C．Na₂CO₃是盐，不是碱；C₂H₅OH是醇，不是盐；Fe(OH)₃胶体是混合物；CuSO₄·5H₂O是纯净物，C错误。
D．NaHSO₄是酸式盐；浓硫酸是混合物；冰水只含H₂O，是纯净物；NO是不成盐氧化物，D错误。
故选B。$exp08$),
('--:H1_CLASSIFY-33625324a822eacf','H1_CLASSIFY-33625324a822eacf','高一','H1_CLASSIFY',2,'4e17d010f68747864e6157f5a83ed06f112d30f95e1796210ba93e73e279fc9b',false,$exp09$A．丁达尔现象是胶体的性质，可用于区分胶体和溶液，但不是三类分散系的本质区别，A错误。
B．能否通过滤纸是分散质粒子大小不同造成的宏观表现，不是本质区别，B错误。
C．三类分散系按分散质粒子直径分类：溶液小于1 nm，胶体为1～100 nm，浊液大于100 nm，因此C正确。
D．均一性、透明度和稳定性是分散质粒子大小不同造成的外在性质，不是本质区别，D错误。
故选C。$exp09$),
('--:H1_CLASSIFY-4d226212640454b7','H1_CLASSIFY-4d226212640454b7','高一','H1_CLASSIFY',0,'88d892593136f19b307f61f012c6b5ff2c5c23582798d16cfd8ec6c51b15e54b',false,$exp10$A．HNO₃是酸，KOH是碱，CaCO₃是盐，SO₂是酸性氧化物，CaO是碱性氧化物，分类均正确，A正确。
B．CO是不成盐氧化物，不能归为酸性氧化物，B错误。
C．Cu₂(OH)₂CO₃是碱式盐，不是碱；Na₂O₂是过氧化物，不属于碱性氧化物，C错误。
D．Na₂CO₃是盐，不是碱；Mn₂O₇是酸性氧化物，不是碱性氧化物，D错误。
故选A。$exp10$),
('--:H1_CLASSIFY-ccceed6dcf7d08f3','H1_CLASSIFY-ccceed6dcf7d08f3','高一','H1_CLASSIFY',2,'c7513fe72a65e10e4a273d7356daad901e9af6b99337d358ed5e869da813f982',false,$exp11$A．树状分类法是在同一层级按同一标准逐级分类。单质可分为金属单质、非金属单质和稀有气体，A正确。
B．交叉分类法可从不同标准同时分类。Na₂CO₃按阳离子属于钠盐，按盐的组成属于正盐，B正确。
C．碱性氧化物一定是金属氧化物；酸性氧化物不一定是非金属氧化物，例如Mn₂O₇是金属氧化物，也是酸性氧化物，C错误。
D．四种基本反应类型不能包括所有化学反应，例如高炉炼铁的总反应不属于四种基本反应类型，D正确。
故选C。$exp11$),
('--:H1_CLASSIFY-2a250cf77b3b76e3','H1_CLASSIFY-2a250cf77b3b76e3','高一','H1_CLASSIFY',2,'2345e6ef36c25f620670b84139bc14b73e7e3859a7d45dbd551b521f4141c369',false,$exp12$A．纯碱Na₂CO₃属于盐，苛性钠NaOH属于碱，不能都归为碱，A错误。
B．蔗糖在水溶液和熔融状态下都不能电离出自由移动的离子，属于非电解质，B错误。
C．漂白粉含CaCl₂、Ca(ClO)₂等成分，医用酒精是乙醇水溶液，两者都是混合物，C正确。
D．明矾属于盐，石墨是碳单质，不属于盐，D错误。
故选C。$exp12$),
('--:H1_CLASSIFY-adffc0ba2835838d','H1_CLASSIFY-adffc0ba2835838d','高一','H1_CLASSIFY',0,'728e48d1b84dcf02b023c7e54e99db2c63111ff02fe2446acda1f55d6ab8ed7d',false,$exp13$A．泡腾片由多种物质组成，是混合物。电解质和非电解质都只用于化合物分类，因此泡腾片既不是电解质也不是非电解质，A错误。
B．乳糖C₁₂H₂₂O₁₁是化合物，在水溶液中和熔融状态下都不能电离出自由移动的离子，属于非电解质，B正确。
C．维生素C（C₆H₈O₆）是化合物，溶于水能发生电离，属于电解质，C正确。
D．CaCO₃是盐，属于电解质；难溶不等于非电解质，D正确。
故选A。$exp13$),
('--:H1_CLASSIFY-d1f4cc8b19c27f9e','H1_CLASSIFY-d1f4cc8b19c27f9e','高一','H1_CLASSIFY',2,'55a0a533126d90cc3d3f38039ca25ff3eec9d037d1255d80f1a26b661e0e3a4f',false,$exp14$A．CO₂在水中不能自身电离；其水溶液导电是因为CO₂与水反应生成的H₂CO₃发生电离，因此CO₂属于非电解质，A正确。
B．CuO能与酸反应生成盐和水，属于碱性氧化物，B正确。
C．Cu₂(OH)₂CO₃属于碱式盐，不属于碱，C错误。
D．H₂O能发生极弱的电离，属于弱电解质，因此也是电解质，D正确。
故选C。$exp14$),
('--:H1_CLASSIFY-987e4d2538a2023d','H1_CLASSIFY-987e4d2538a2023d','高一','H1_CLASSIFY',2,'67ec0f8aeca68d77a11efa74c410f7fb9062f95d02981b18e9f8b53b05801922',true,$exp15$①同素异形体是同种元素形成的不同单质。H₂O和H₂O₂都是化合物，不互为同素异形体，①错误。
②酸性氧化物可能是金属氧化物，例如Mn₂O₇；非金属氧化物也可能是不成盐氧化物，例如CO、NO，②错误。
③碱性氧化物一定是金属氧化物，因此一定含金属元素，③正确。
④胆矾是纯净物，碱石灰是混合物，纯碱Na₂CO₃是盐，不是碱，④错误。
⑤酸根中含H不一定就是酸式盐，例如Na₂HPO₃是正盐，⑤错误。
⑥CO₂水溶液导电是因为生成的H₂CO₃发生电离；CO₂自身不能电离，属于非电解质，⑥错误。
⑦酸的元数按每个酸分子能够电离出的H⁺数目判断，不按化学式中H原子总数判断；H₃PO₂是一元酸，⑦错误。
只有③正确，共1项，故选C。$exp15$),
('--:H1_REDOX-32cd27f36c85adce','H1_REDOX-32cd27f36c85adce','高一','H1_REDOX',0,'455774ff91d441c3005aa1c75b09d4cf7f4e78f86a5dcf59ad79280f0c84a21e',false,$exp16$A．SO₂＋2NaOH＝Na₂SO₃＋H₂O中没有元素化合价变化，红色褪去是碱被消耗造成的，与氧化还原反应无关，A正确。
B．新制氯水中的HCl使石蕊先变红，HClO再通过氧化作用使其褪色，褪色与氧化还原反应有关，B错误。
C．酸性KMnO₄具有强氧化性，能氧化植物油中的不饱和键，紫红色褪去与氧化还原反应有关，C错误。
D．浓硝酸久置产生NO₂而显黄色；通入空气后发生4NO₂＋O₂＋2H₂O＝4HNO₃，存在化合价变化，D错误。
故选A。$exp16$),
('--:H1_REDOX-823e63f4c62c1b2c','H1_REDOX-823e63f4c62c1b2c','高一','H1_REDOX',1,'cd30bf200af09de3c1ae2e2f5ca7c1c70b14053b0627a1bb9548fc4611ad9fc8',false,$exp17$A．ClO⁻中Cl的化合价降低，ClO⁻是氧化剂；N₂是氧化产物。同一反应中氧化剂的氧化性强于氧化产物，因此氧化性ClO⁻＞N₂，A正确。
B．NH₄⁺中N由－3价升到0价，NH₄⁺是还原剂；Cl⁻是还原产物。同一反应中还原剂的还原性强于还原产物，因此还原性NH₄⁺＞Cl⁻，B错误。
C．N由－3价升到0价，被氧化；Cl由＋1价降到－1价，被还原，C正确。
D．方程式生成H⁺，处理后的废水呈酸性，不能不经处理直接排放，D正确。
故选B。$exp17$),
('--:H1_REDOX-c8386ad877846bee','H1_REDOX-c8386ad877846bee','高一','H1_REDOX',3,'0d6d7dac71db9a10fbfdcc7f7b09ae921ba6250b7bba1e624250b34eadf2413f',false,$exp18$A．O₂中O由0价降为－2价，O₂得电子，作氧化剂，A正确。
B．Cu₂S中S为－2价，根据化合价代数和为0，可得Cu为＋1价，B正确。
C．生成SO₂时，S由－2价升为＋4价，O由0价降为－2价，所以SO₂既是氧化产物又是还原产物，C正确。
D．1 mol O₂参加反应时转移6 mol电子。2.408×10²³个电子为0.4 mol电子，消耗O₂为0.4÷6＝1/15 mol，不是0.1 mol，D错误。
故选D。$exp18$),
('--:H1_REDOX-aa573ff7128d569d','H1_REDOX-aa573ff7128d569d','高一','H1_REDOX',2,'cc3048a85f1f1e0af0049858184ab172b2fc304492144caee25f9c9d4cbf4f1c',false,$exp19$A．KClO₃与HCl反应时，Cl₂中既有由－1价升到0价的Cl，也有由＋5价降到0价的Cl，所以Cl₂既是氧化产物又是还原产物，A错误。
B．浓H₂SO₄中S为＋6价，SO₂中S为＋4价，二者之间没有可共同转化的中间价态，通常不反应；浓H₂SO₄可以干燥SO₂，B错误。
C．H₂S中的S由－2价升到0价，生成的S是氧化产物；H₂SO₄中的S由＋6价降到＋4价，生成的SO₂是还原产物。方程式中二者系数均为1，物质的量之比为1∶1，C正确。
D．NO₂具有氧化性，在一定条件下可以氧化NH₃，D错误。
故选C。$exp19$),
('--:H1_REDOX-5fc4ddefb3d73b3e','H1_REDOX-5fc4ddefb3d73b3e','高一','H1_REDOX',2,'a62835405f9afccfe714610dc93c77e245c454a476c82fea1bc59d331cf51836',false,$exp20$A．该反应中SO₂是还原剂，Fe²⁺是还原产物。题给还原性SO₂＞Fe²⁺，符合“还原剂＞还原产物”，反应能发生，A错误。
B．该反应中Fe²⁺是还原剂，Cl⁻是还原产物。题给还原性Fe²⁺＞Cl⁻，反应能发生，B错误。
C．题给还原性Br⁻＜SO₂，而该式把Br⁻作为还原剂、SO₂作为还原产物，违背“还原剂＞还原产物”，反应不能按所写方向发生，C正确。
D．该反应中SO₂是还原剂，I⁻是还原产物。题给还原性SO₂＞I⁻，反应能发生，D错误。
故选C。$exp20$),
('--:H1_REDOX-96bc425d5fc494b8','H1_REDOX-96bc425d5fc494b8','高一','H1_REDOX',1,'41ba76155a6d81a5c314af3b6a3749db878c859c475badb102446f8e858db68b',false,$exp21$A．NbO⁺中Nb为＋3价，NbO₂⁺中Nb为＋5价，题中顺序写反，A错误。
B．反应前后H均为＋1价，H⁺中H的化合价没有变化，因此H⁺既不是氧化剂也不是还原剂，B正确。
C．NbO₂⁺和Nb₂O₅中Nb均为＋5价，转化时没有元素化合价变化，不是氧化还原反应，C错误。
D．Nb由＋3价升到＋5价，每生成1 mol NbO₂⁺转移2 mol电子；生成0.1 mol时转移0.2 mol电子，D错误。
故选B。$exp21$),
('--:H1_REDOX-a7147f4559791b52','H1_REDOX-a7147f4559791b52','高一','H1_REDOX',1,'fa74e22fa0e8776097c6aa6dfd173b600d5be6dc863f03bacdbde55650bd2a44',false,$exp22$A．反应①中S₂O₃²⁻发生歧化，既作氧化剂又作还原剂；反应⑤只是配合反应，不是氧化还原反应，S₂O₃²⁻既不是氧化剂也不是还原剂，因此A错误。
B．反应②中2 mol S₂O₃²⁻共转移2 mol电子，即1 mol S₂O₃²⁻转移1 mol电子；消耗0.1 mol时转移电子数为0.1N_A，B正确。
C．反应④中各元素化合价均未变化，是非氧化还原反应，没有氧化剂和还原剂，C错误。
D．S₂O₈²⁻中S为＋6价；其中有2个过氧键中的O为－1价，强氧化性来自－1价O，不是“＋7价硫”，D错误。
故选B。$exp22$),
('--:H2_WEAK-9892e9de94a6e82f','H2_WEAK-9892e9de94a6e82f','高二','H2_WEAK',1,'4543a19892b694cc1fb85619ca8fb4171586d4d7b472fa1cafe1df21aea4d9ff',false,$exp23$A．X点HA溶液稀释10倍时pH变化小于1，说明HA是弱酸；Y点MOH溶液稀释10倍时pH减小1，说明MOH是强碱，A错误。
B．X点pH＝5，由水电离出的c(H⁺)＝10⁻⁹ mol·L⁻¹；Y、Z点的c(OH⁻)分别为10⁻⁴、10⁻⁵ mol·L⁻¹，由水电离出的c(H⁺)分别为10⁻¹⁰、10⁻⁹ mol·L⁻¹，所以水的电离程度X＝Z＞Y，B正确。
C．升高温度会使Kᵥ改变，Y、Z点对应溶液的pH都会改变，C错误。
D．X点HA溶液与Z点MOH溶液等体积混合并中和后，HA仍有剩余，所得溶液呈酸性，D错误。
故选B。$exp23$),
('--:H2_WEAK-491d899198f83620','H2_WEAK-491d899198f83620','高二','H2_WEAK',0,'d77bc43ae4fd456e536e7a04ff0c1d7e1e4942459e43b03ac21fe427e53464b8',false,$exp24$A．NaCl和NaH₂PO₂都是盐，均为强电解质。比较等浓度两种盐溶液的导电性，不能证明H₃PO₂是否为弱电解质，A错误。
B．等体积、等pH时，若次磷酸是弱酸，其总物质的量大于盐酸；完全中和时会消耗更多同浓度NaOH，可据此证明，B正确。
C．若H₃PO₂是弱酸，H₂PO₂⁻会水解使NaH₂PO₂溶液呈碱性；加热促进水解，酚酞颜色变深，可据此证明，C正确。
D．若0.1 mol·L⁻¹ H₃PO₂为一元强酸，稀释100倍后pH应为3；实测pH为4～5，说明它未完全电离，是弱电解质，D正确。
故选A。$exp24$),
('--:H2_WEAK-79e7718da63cf2c2','H2_WEAK-79e7718da63cf2c2','高二','H2_WEAK',2,'b30c89c39a520daec232dcb04204a3a0d28ac045f70780a05377d1a91732c53f',false,$exp25$A．由电离常数得酸性H₂CO₃＞HClO＞HCO₃⁻。向Na₂CO₃溶液滴加少量氯水时应生成HCO₃⁻和ClO⁻，正确离子方程式为2CO₃²⁻＋Cl₂＋H₂O＝Cl⁻＋2HCO₃⁻＋ClO⁻，A错误。
B．向NaHCO₃溶液滴加少量氯水，正确离子方程式为HCO₃⁻＋Cl₂＝Cl⁻＋HClO＋CO₂↑，B错误。
C．少量CO₂通入NaClO溶液时，较强酸制较弱酸，生成NaHCO₃和HClO，所给方程式正确，C正确。
D．过量CO₂通入NaClO溶液仍生成NaHCO₃和HClO，不生成Na₂CO₃，D错误。
故选C。$exp25$),
('--:H2_WEAK-fa24846e936c694c','H2_WEAK-fa24846e936c694c','高二','H2_WEAK',3,'e101627547bed463d2e7e17530a414a83f0b68e592ac352911a0565cf4024073',false,$exp26$A．M、N两点pH都为3。由电荷守恒，M点c(A⁻)＝c(H⁺)－c(OH⁻)，N点c(B⁻)＝c(H⁺)－c(OH⁻)，因此二者相等，A正确。
B．1 mol·L⁻¹ HA溶液pH＝2，近似有c(H⁺)＝c(A⁻)＝10⁻² mol·L⁻¹、c(HA)≈1 mol·L⁻¹，所以Kₐ≈10⁻⁴，B正确。
C．0.1 mol·L⁻¹ NaA与0.1 mol·L⁻¹ HA组成等浓度的弱酸及其盐混合液，c(H⁺)约为Kₐ＝10⁻⁴ mol·L⁻¹，pH约为4，小于7，C正确。
D．稀释不改变酸的物质的量，M、P两点所含一元酸的物质的量相等；完全中和时消耗等浓度NaOH的体积相等，不是P＞M，D错误。
故选D。$exp26$),
('--:H2_WEAK-ff6cdf012f6ed33b','H2_WEAK-ff6cdf012f6ed33b','高二','H2_WEAK',2,'616655570b854985d091a41561241fc104589a8d72dad3c99a55bb1731fa54a9',false,$exp27$A．同一温度下，同一种弱酸HX的电离常数只与温度有关，因此K₁＝K₂＝K₃；浓度越低时电离度越大，但电离常数不变，A错误。
B．NaZ溶液中Kₕ＝c(HZ)·c(OH⁻)/c(Z⁻)。加少量盐酸后平衡移动，但温度不变，Kₕ不变，所以其倒数c(Z⁻)/[c(HZ)·c(OH⁻)]也不变，B错误。
C．对一元弱酸，c(X⁻)可由初始浓度与电离度的乘积比较。按表中三组数据计算，c(X⁻)从左到右逐渐增大，C正确。
D．同温、同浓度时，电离度越大，电离常数越大。由表中数据应有K₅＞K₄＞K₃，D错误。
故选C。$exp27$),
('--:H2_WEAK-ca1394bd60a7c25b','H2_WEAK-ca1394bd60a7c25b','高二','H2_WEAK',2,'bc254b1098903f06f0cae958ec63ea10422a004ef805a4619ba2a0ba1b947d8a',false,$exp28$A．强酸进入体液后c(H⁺)增大，平衡向左移动并消耗一部分H⁺，有助于维持pH相对稳定，A合理。
B．强碱进入体液后会消耗H⁺，平衡向右移动并补充一部分H⁺，有助于维持pH相对稳定，B合理。
C．大量生理盐水使体液被稀释。平衡虽向右移动，但只能减弱稀释造成的变化，最终c(H⁺)减小、pH增大，不是pH减小，C不合理。
D．CO₂进入血液后推动平衡向右移动，c(H⁺)增大，体液pH减小，D合理。
故选C。$exp28$),
('--:H2_WEAK-2168fc53f896e5cd','H2_WEAK-2168fc53f896e5cd','高二','H2_WEAK',0,'e895bc1bf93cc748c67f88a391235ebb294e9adc1d1f73b6f10259b7a3e66635',false,$exp29$A．加入NaOH后，OH⁻消耗H⁺，c(H⁺)减小，HCN的电离平衡向右移动，A正确。
B．加水稀释会促进弱电解质电离，HCN的电离平衡向右移动，不是向左，B错误。
C．HCl是强电解质，加入少量0.1 mol·L⁻¹ HCl会使溶液中c(H⁺)增大，不是减小，C错误。
D．加入NaCN使c(CN⁻)增大，发生同离子效应，HCN的电离平衡向左移动，D错误。
故选A。$exp29$),
('--:H2_WEAK-0d492adf15dececc','H2_WEAK-0d492adf15dececc','高二','H2_WEAK',2,'7a973616d66bcecc6902bc24962c26366e4922129effa4a5eaf3759ae26fcb3c',false,$exp30$A．同温度下电离常数越大，酸性越强。Kₐ(HX)＝7.8×10⁻⁹＞Kₐ(HY)＝3.7×10⁻¹⁵，所以酸性HX＞HY，A错误。
B．酸越弱，其对应酸根水解程度越大。由各级电离常数比较，相同条件下碱性顺序为NaY＞Na₂CO₃＞NaX＞NaHCO₃，B错误。
C．Kₐ(HX)＞Kₐ₂(H₂CO₃)，HX能把CO₃²⁻转化为HCO₃⁻；同时Kₐ(HX)＜Kₐ₁(H₂CO₃)，不会继续生成H₂CO₃，因此HX＋CO₃²⁻＝HCO₃⁻＋X⁻正确，C正确。
D．弱酸溶液中c(H⁺)不仅取决于电离常数，还取决于溶液浓度；题目未给HX、HY溶液浓度，不能直接比较，D错误。
故选C。$exp30$),
('--:H2_WEAK-4e52f1af37ddc684','H2_WEAK-4e52f1af37ddc684','高二','H2_WEAK',2,'c39f0e5b3b064a734705b0ab43928736395a5f61b6e977e3b8db5e64e92a4069',false,$exp31$A．近似计算c(H⁺)＝√[Kₐ·c(CH₃COOH)]＝√(1.75×10⁻⁶) mol·L⁻¹，pH约为2.88，在2～3之间，A正确。
B．CH₃COONa溶液的质子守恒式为c(CH₃COOH)＋c(H⁺)＝c(OH⁻)，B正确。
C．温度不变时Kₐ不变；但c(H⁺)/c(CH₃COOH)＝Kₐ/c(CH₃COO⁻)，加水稀释时c(CH₃COO⁻)减小，所以该比值增大，不是保持不变，C错误。
D．等物质的量NaOH与CH₃COOH恰好反应后，溶液中主要溶质为CH₃COONa，水解使pH＞7，并有c(Na⁺)＞c(CH₃COO⁻)＞c(OH⁻)＞c(H⁺)，D正确。
故选C。$exp31$),
('--:H2_WEAK-7ca438636748081a','H2_WEAK-7ca438636748081a','高二','H2_WEAK',0,'59767ca20db48fea1a027f6bf849cbf6f3c7e57078044474998e87facd1699f0',false,$exp32$A．a点pH＝7，H₂S与SO₂恰好完全反应，水的电离程度最大；a点前H₂S过量，a点后SO₂过量，酸都会抑制水的电离，所以全过程水的电离程度先增大后减小，A正确。
B．起点pH＝4.1，c(H⁺)＝10⁻⁴·¹ mol·L⁻¹，c(H₂S)约为0.1 mol·L⁻¹，Kₐ₁≈(10⁻⁴·¹)²/(0.1－10⁻⁴·¹)≈10⁻⁷·²，写成科学计数法的数量级为10⁻⁸，B错误。
C．通入336 mL SO₂时，溶液中H₂SO₃浓度约为0.1 mol·L⁻¹；H₂SO₃酸性强于H₂S，此时pH应小于4.1，因此应对应曲线y，不是x，C错误。
D．c(HSO₃⁻)/c(H₂SO₃)＝Kₐ₁/c(H⁺)。a点后c(H⁺)先增大，SO₂达到饱和后不再变化，所以该比值先减小后不变，不是始终减小，D错误。
故选A。$exp32$),
('--:H2_WEAK-960cac557c2163f1','H2_WEAK-960cac557c2163f1','高二','H2_WEAK',1,'442709af0e1614cd8270c8eb6a37de89698019a56cee5f5df09418be37a7cdfc',false,$exp33$A．加水稀释促进NH₃·H₂O电离，电离程度增大，A正确。
B．虽然电离程度增大，但溶液体积由10 mL增至1 L，c(NH₃·H₂O)减小，不是增大，B错误。
C．稀释促进电离，电离出的NH₄⁺物质的量增大，因此NH₄⁺的数目增多，C正确。
D．稀释后c(OH⁻)减小；温度不变时c(H⁺)·c(OH⁻)＝Kᵥ，所以c(H⁺)增大，D正确。
故选B。$exp33$),
('--:H2_WEAK-f8e447fd573d6be7','H2_WEAK-f8e447fd573d6be7','高二','H2_WEAK',1,'fd9d9064c17b3c2c3dd835de52e238579339e1c9e07d29cedb9f1fef5846d6c8',false,$exp34$A．较强酸可以制取较弱酸。由三个反应可得酸性HF＞HNO₂＞HCN，因此HF的电离常数最大，为7.2×10⁻⁴，A正确。
B．HNO₂酸性介于HF和HCN之间，其电离常数应为中间值4.6×10⁻⁴，不是4.9×10⁻¹⁰，B错误。
C．由NaCN＋HNO₂反应可得HNO₂＞HCN，再由NaNO₂＋HF反应可得HF＞HNO₂，两条反应即可得到HF＞HNO₂＞HCN，C正确。
D．同温度下酸性越强，电离常数越大，因此K(HCN)＜K(HNO₂)＜K(HF)，D正确。
故选B。$exp34$);

create temporary table _h3_active_release_before on commit drop as
select id
from app_private.chem_question_source_releases
where grade_band = '高三' and status = 'active';

do $guard$
declare
  v_count integer;
begin
  if (select count(*) from _explanation_release_spec) <> 2 then
    raise exception 'replacement release specification must contain exactly H1 and H2';
  end if;
  if exists (
    select 1 from _explanation_release_spec
    where (grade_band, expected_question_count) not in (('高一',125),('高二',200))
  ) then
    raise exception 'replacement release grade/count specification is invalid';
  end if;
  if exists (
    select 1
    from _explanation_release_spec s
    left join app_private.chem_question_source_releases r
      on r.id = s.old_release_id
     and r.manifest_sha256 = s.old_manifest_sha256
     and r.grade_band = s.grade_band
     and r.status = 'active'
     and r.verification_status = 'full_visual_verified'
    where r.id is null
  ) then
    raise exception 'the active H1/H2 release differs from the audited source release; refusing to guess';
  end if;
  if exists (
    select 1
    from _explanation_release_spec s
    join app_private.chem_question_source_releases r
      on r.id = s.new_release_id or r.manifest_sha256 = s.new_manifest_sha256
  ) then
    raise exception 'a replacement release identity already exists';
  end if;
  if (select count(*) from _explanation_overrides) <> 34 then
    raise exception 'exactly 34 source-checked explanations are required';
  end if;
  if (select count(*) from _explanation_overrides where skill_id='H1_CLASSIFY') <> 15
    or (select count(*) from _explanation_overrides where skill_id='H1_REDOX') <> 7
    or (select count(*) from _explanation_overrides where skill_id='H2_WEAK') <> 12
  then
    raise exception 'the explanation skill distribution is not 15/7/12';
  end if;
  if exists (
    select 1
    from _explanation_overrides o
    left join _explanation_release_spec s on s.grade_band = o.grade_band
    left join app_private.chem_question_source_release_items ri
      on ri.release_id = s.old_release_id
     and ri.canonical_source_id = o.canonical_source_id
    left join public.chem_questions q
      on q.id = ri.question_id
     and q.source_release_id = s.old_release_id
    where q.id is null
       or q.skill_id is distinct from o.skill_id
       or q.correct_option is distinct from o.correct_option
       or ri.analysis_asset_sha256 is distinct from o.analysis_asset_sha256
  ) then
    raise exception 'an override does not match its audited source question, answer, skill, or analysis image';
  end if;
  select count(*) into v_count
  from public.chem_questions q
  join _explanation_release_spec s on s.old_release_id = q.source_release_id;
  if v_count <> 325 then
    raise exception 'active H1/H2 source inventory is %, expected 325', v_count;
  end if;
  if exists (
    select 1
    from _explanation_release_spec s
    left join lateral (
      select count(*) as questions
      from public.chem_questions q
      where q.source_release_id = s.old_release_id
    ) q_count on true
    left join lateral (
      select count(*) as items
      from app_private.chem_question_source_release_items ri
      where ri.release_id = s.old_release_id
    ) i_count on true
    left join lateral (
      select count(*) as assets
      from app_private.chem_question_assets a
      join public.chem_questions q on q.id = a.question_id
      where q.source_release_id = s.old_release_id
    ) a_count on true
    where q_count.questions <> s.expected_question_count
       or i_count.items <> s.expected_question_count
       or a_count.assets <> s.expected_question_count * 2
  ) then
    raise exception 'the active source inventory is incomplete';
  end if;
end;
$guard$;

insert into app_private.chem_question_source_releases(
  id, manifest_sha256, grade_band, status, expected_question_count,
  verification_status
)
select
  new_release_id, new_manifest_sha256, grade_band, 'staged',
  expected_question_count, 'pending'
from _explanation_release_spec;

create temporary table _replacement_question_map (
  grade_band text not null,
  old_release_id uuid not null,
  new_release_id uuid not null,
  old_question_id text primary key,
  new_question_id text not null unique,
  canonical_source_id text not null,
  question_asset_sha256 text not null,
  analysis_asset_sha256 text not null
) on commit drop;

insert into _replacement_question_map(
  grade_band, old_release_id, new_release_id,
  old_question_id, new_question_id, canonical_source_id,
  question_asset_sha256, analysis_asset_sha256
)
select
  s.grade_band,
  s.old_release_id,
  s.new_release_id,
  q.id,
  q.id || '_R761DC1B48D41',
  ri.canonical_source_id,
  ri.question_asset_sha256,
  ri.analysis_asset_sha256
from _explanation_release_spec s
join public.chem_questions q on q.source_release_id = s.old_release_id
join app_private.chem_question_source_release_items ri
  on ri.release_id = s.old_release_id
 and ri.question_id = q.id;

insert into public.chem_questions(
  id, mother_id, skill_id, level, grade_band,
  stem, options, correct_option, explanation, scaffold,
  review_status, scope_status, source_kind, image_url,
  usable_for_class_quiz, usable_for_review, usable_for_exam_sprint,
  concept_key, source_info, asset_refs, render_mode,
  source_item_key, content_fingerprint, question_revision_token,
  source_release_id, usable_for_demo
)
select
  m.new_question_id,
  q.mother_id,
  q.skill_id,
  q.level,
  q.grade_band,
  q.stem,
  q.options,
  q.correct_option,
  coalesce(o.explanation, q.explanation),
  null,
  'approved',
  'IN',
  'licensed_local',
  null,
  false,
  false,
  false,
  q.concept_key,
  q.source_info,
  (
    select jsonb_agg(
      ref || jsonb_build_object('path', (ref->>'path') || '/r761dc1b48d41')
      order by ordinal
    )
    from jsonb_array_elements(q.asset_refs) with ordinality as asset(ref, ordinal)
  ),
  'image_primary',
  q.source_item_key,
  q.content_fingerprint,
  q.question_revision_token,
  m.new_release_id,
  false
from _replacement_question_map m
join public.chem_questions q on q.id = m.old_question_id
left join _explanation_overrides o
  on o.canonical_source_id = m.canonical_source_id;

insert into app_private.chem_question_assets(
  asset_path, question_id, asset_kind, mime_type,
  payload_base64, sha256, width, height
)
select
  a.asset_path || '/r761dc1b48d41',
  m.new_question_id,
  a.asset_kind,
  a.mime_type,
  a.payload_base64,
  a.sha256,
  a.width,
  a.height
from _replacement_question_map m
join app_private.chem_question_assets a on a.question_id = m.old_question_id;

update public.chem_questions q
set question_revision_token = app_private.chem_h3_question_revision_sha256(
      q,
      question_asset.sha256,
      analysis_asset.sha256
    ),
    updated_at = now()
from _replacement_question_map m,
     app_private.chem_question_assets question_asset,
     app_private.chem_question_assets analysis_asset
where q.id = m.new_question_id
  and question_asset.question_id = q.id
  and question_asset.asset_kind = 'question_image'
  and analysis_asset.question_id = q.id
  and analysis_asset.asset_kind = 'analysis_image';

insert into app_private.chem_question_source_release_items(
  release_id, question_id, canonical_source_id,
  question_asset_sha256, analysis_asset_sha256, item_sha256
)
select
  m.new_release_id,
  q.id,
  m.canonical_source_id,
  m.question_asset_sha256,
  m.analysis_asset_sha256,
  app_private.chem_h3_release_item_sha256(
    q,
    m.canonical_source_id,
    m.question_asset_sha256,
    m.analysis_asset_sha256
  )
from _replacement_question_map m
join public.chem_questions q on q.id = m.new_question_id;

do $qa$
declare
  v_manifest text;
  v_spec record;
begin
  if (select count(*) from _replacement_question_map) <> 325 then
    raise exception 'replacement question map must contain exactly 325 questions';
  end if;
  if (select count(*) from public.chem_questions q join _explanation_release_spec s on s.new_release_id=q.source_release_id) <> 325 then
    raise exception 'replacement releases do not contain exactly 325 questions';
  end if;
  if (select count(*) from app_private.chem_question_assets a join _replacement_question_map m on m.new_question_id=a.question_id) <> 650 then
    raise exception 'replacement releases do not contain exactly 650 assets';
  end if;
  if (select count(*) from app_private.chem_question_source_release_items ri join _explanation_release_spec s on s.new_release_id=ri.release_id) <> 325 then
    raise exception 'replacement release ledger does not contain exactly 325 items';
  end if;
  if exists (
    select 1
    from _replacement_question_map m
    join public.chem_questions old_q on old_q.id = m.old_question_id
    join public.chem_questions new_q on new_q.id = m.new_question_id
    left join _explanation_overrides o on o.canonical_source_id = m.canonical_source_id
    where new_q.id <> old_q.id || '_R761DC1B48D41'
       or new_q.mother_id is distinct from old_q.mother_id
       or new_q.skill_id is distinct from old_q.skill_id
       or new_q.concept_key is distinct from old_q.concept_key
       or new_q.level is distinct from old_q.level
       or new_q.grade_band is distinct from old_q.grade_band
       or new_q.stem is distinct from old_q.stem
       or new_q.options is distinct from old_q.options
       or new_q.correct_option is distinct from old_q.correct_option
       or new_q.source_info is distinct from old_q.source_info
       or new_q.source_item_key is distinct from old_q.source_item_key
       or new_q.content_fingerprint is distinct from old_q.content_fingerprint
       or new_q.scaffold is not null
       or new_q.image_url is not null
       or new_q.question_revision_token is not distinct from old_q.question_revision_token
       or new_q.explanation is distinct from coalesce(o.explanation, old_q.explanation)
  ) then
    raise exception 'a replacement question changed outside the allowed identity/explanation fields';
  end if;
  if (
    select count(*)
    from _replacement_question_map m
    join public.chem_questions old_q on old_q.id=m.old_question_id
    join public.chem_questions new_q on new_q.id=m.new_question_id
    where new_q.explanation is distinct from old_q.explanation
  ) <> 34 then
    raise exception 'the replacement release must change exactly 34 explanations';
  end if;
  if exists (
    select 1
    from _replacement_question_map m
    join app_private.chem_question_assets old_a on old_a.question_id=m.old_question_id
    left join app_private.chem_question_assets new_a
      on new_a.question_id=m.new_question_id
     and new_a.asset_kind=old_a.asset_kind
    where new_a.asset_path is null
       or new_a.asset_path <> old_a.asset_path || '/r761dc1b48d41'
       or new_a.mime_type is distinct from old_a.mime_type
       or new_a.payload_base64 is distinct from old_a.payload_base64
       or new_a.sha256 is distinct from old_a.sha256
       or new_a.width is distinct from old_a.width
       or new_a.height is distinct from old_a.height
  ) then
    raise exception 'a replacement asset is missing or differs from the previously verified image bytes';
  end if;
  if exists (
    select 1
    from _explanation_overrides o
    join _replacement_question_map m on m.canonical_source_id=o.canonical_source_id
    join public.chem_questions q on q.id=m.new_question_id
    where q.explanation is distinct from o.explanation
       or q.explanation ~ '(学科网|股份有限公司|原题来源|来源：|题面PDF|解析PDF|原解析图|下一题|�|↵|物理页[[:space:]]*[0-9]+)'
       or (
         not o.is_combination
         and not (
           strpos(q.explanation,'A．') > 0
           and strpos(q.explanation,'B．') > strpos(q.explanation,'A．')
           and strpos(q.explanation,'C．') > strpos(q.explanation,'B．')
           and strpos(q.explanation,'D．') > strpos(q.explanation,'C．')
         )
       )
       or (
         o.is_combination
         and not (
           strpos(q.explanation,'①') > 0
           and strpos(q.explanation,'②') > strpos(q.explanation,'①')
           and strpos(q.explanation,'③') > strpos(q.explanation,'②')
           and strpos(q.explanation,'④') > strpos(q.explanation,'③')
           and strpos(q.explanation,'⑤') > strpos(q.explanation,'④')
           and strpos(q.explanation,'⑥') > strpos(q.explanation,'⑤')
           and strpos(q.explanation,'⑦') > strpos(q.explanation,'⑥')
         )
       )
  ) then
    raise exception 'an explanation is incomplete, unsegmented, or contains source/page/carry-over text';
  end if;
  if exists (
    select 1
    from _replacement_question_map m
    join public.chem_questions q on q.id=m.new_question_id
    join app_private.chem_question_assets qa
      on qa.question_id=q.id and qa.asset_kind='question_image'
    join app_private.chem_question_assets aa
      on aa.question_id=q.id and aa.asset_kind='analysis_image'
    join app_private.chem_question_source_release_items ri
      on ri.release_id=m.new_release_id and ri.question_id=q.id
    where q.question_revision_token is distinct from
            app_private.chem_h3_question_revision_sha256(q,qa.sha256,aa.sha256)
       or ri.item_sha256 is distinct from
            app_private.chem_h3_release_item_sha256(q,ri.canonical_source_id,qa.sha256,aa.sha256)
       or ri.question_asset_sha256 is distinct from qa.sha256
       or ri.analysis_asset_sha256 is distinct from aa.sha256
  ) then
    raise exception 'a replacement revision token or ledger digest is invalid';
  end if;
  for v_spec in select * from _explanation_release_spec order by grade_band loop
    select pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to(
          pg_catalog.string_agg(ri.item_sha256, E'\n' order by ri.question_id),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
    into v_manifest
    from app_private.chem_question_source_release_items ri
    where ri.release_id=v_spec.new_release_id;
    if v_manifest is distinct from v_spec.new_manifest_sha256 then
      raise exception '% replacement manifest is %, expected %',
        v_spec.grade_band, v_manifest, v_spec.new_manifest_sha256;
    end if;
  end loop;
end;
$qa$;

select public.chem_mark_source_original_release_visually_verified(
  new_release_id,
  new_manifest_sha256,
  'codex-full-visual-qa'
)
from _explanation_release_spec
order by grade_band;

do $activate$
declare
  v_spec record;
begin
  for v_spec in select * from _explanation_release_spec order by grade_band loop
    perform public.chem_activate_source_original_release(
      v_spec.new_release_id,
      v_spec.new_manifest_sha256
    );
  end loop;
end;
$activate$;

do $postcondition$
begin
  if exists (
    select 1
    from _explanation_release_spec s
    left join app_private.chem_question_source_releases new_r
      on new_r.id=s.new_release_id and new_r.status='active'
    left join app_private.chem_question_source_releases old_r
      on old_r.id=s.old_release_id and old_r.status='retired'
    where new_r.id is null or old_r.id is null
  ) then
    raise exception 'replacement releases were not activated with rollback releases retained';
  end if;
  if exists (
    select 1
    from _explanation_release_spec s
    left join lateral (
      select count(*) as enabled
      from public.chem_questions q
      where q.source_release_id=s.new_release_id and q.usable_for_review
    ) enabled_count on true
    where enabled_count.enabled <> s.expected_question_count
  ) then
    raise exception 'an activated replacement release exposes the wrong question count';
  end if;
  if exists (
    (select id from app_private.chem_question_source_releases where grade_band='高三' and status='active')
    except
    (select id from _h3_active_release_before)
  ) or exists (
    (select id from _h3_active_release_before)
    except
    (select id from app_private.chem_question_source_releases where grade_band='高三' and status='active')
  ) then
    raise exception 'H3 active release changed unexpectedly';
  end if;
end;
$postcondition$;

commit;
