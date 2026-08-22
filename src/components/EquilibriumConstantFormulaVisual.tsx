export function EquilibriumConstantFormulaVisual() {
  return <figure className="equilibrium-constant-visual" aria-label="浓度平衡常数怎么写">
    <figcaption><span>公式图</span><b>浓度平衡常数怎么写</b></figcaption>
    <p className="equilibrium-reaction" aria-label="a A 加 b B 可逆生成 c C 加 d D">
      <i>a</i>A + <i>b</i>B ⇌ <i>c</i>C + <i>d</i>D
    </p>
    <div className="equilibrium-constant-equation" aria-label="K c 等于 c 的 c 次方括号 C 乘 c 的 d 次方括号 D，除以 c 的 a 次方括号 A 乘 c 的 b 次方括号 B">
      <strong>K<sub>c</sub></strong>
      <b aria-hidden="true">＝</b>
      <span className="equilibrium-fraction">
        <span className="equilibrium-numerator" aria-label="分子：生成物浓度的化学计量数次方相乘">
          <span className="equilibrium-term"><i>c</i>(C)<sup>c</sup></span>
          <span aria-hidden="true">·</span>
          <span className="equilibrium-term"><i>c</i>(D)<sup>d</sup></span>
        </span>
        <span className="equilibrium-denominator" aria-label="分母：反应物浓度的化学计量数次方相乘">
          <span className="equilibrium-term"><i>c</i>(A)<sup>a</sup></span>
          <span aria-hidden="true">·</span>
          <span className="equilibrium-term"><i>c</i>(B)<sup>b</sup></span>
        </span>
      </span>
    </div>
    <div className="equilibrium-formula-notes">
      <span><b>上面</b>生成物</span>
      <span><b>下面</b>反应物</span>
      <span><b>指数</b>对应化学计量数</span>
      <span><b>浓度</b>都取平衡浓度</span>
    </div>
    <p className="equilibrium-formula-boundary">纯固体、纯液体的浓度视为常数，不写入浓度平衡常数表达式。</p>
  </figure>
}
