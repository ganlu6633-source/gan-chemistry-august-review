// The final month follows the user's Sujiao compulsory-book-1 contents.
// These dates are a syllabus outline, not published quizzes: no question is
// released until its source image, options and teacher explanation are checked.
const units = [
  ['含硫化合物的性质', ['硫的常见化合价', '二氧化硫的酸性', '二氧化硫的氧化性与还原性', '二氧化硫的漂白性', '浓硫酸的性质']],
  ['硫及其化合物的相互转化', ['硫—二氧化硫—三氧化硫转化', '不同价态硫的氧化还原', '硫酸根的检验', '硫专题回看']],
  ['防治二氧化硫对环境的污染', ['酸雨的形成', '烟气脱硫原理', '硫循环与环境治理', '硫与环境专题回看']],
  ['元素周期律和元素周期表', ['原子结构与周期表位置', '同周期性质递变', '同主族性质递变', '金属性、非金属性与半径', '元素周期律回看']],
  ['微粒之间的相互作用力', ['离子键', '共价键', '电子式与结构式', '化学键专题回看']],
  ['从微观结构看物质的多样性', ['同素异形体与同分异构', '微观结构与物质性质', '微观结构专题回看']],
  ['全册综合回看', ['分类与反应规律', '物质的量与溶液定量', '氯、钠、海洋资源', '硫与环境保护', '周期律与物质结构']],
] as const

export const HIGH1_SEMESTER_REMAINING_DAYS = units.flatMap(([unit, topics]) =>
  topics.map((topic) => ({ unit, topic }))
).map((entry, offset) => {
  const date = new Date(Date.UTC(2026, 10, 12 + offset)).toISOString().slice(0, 10)
  return { ...entry, date }
})
