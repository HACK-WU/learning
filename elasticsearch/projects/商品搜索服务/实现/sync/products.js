/**
 * 模拟数据源：一张"商品表"。
 *
 * 定位说明（对应课 14 的核心结论）：
 *   这份数据就是"原始账本"，ES 里的索引只是它的**副本**——
 *   ES 全删了，从这张表重新跑一次 npm run sync 就能完整重建。
 *   真实项目里这张表是 MySQL / PostgreSQL，这里用代码生成以便随时重建。
 *
 * 生成方式是确定性的（线性同余伪随机），所以任何人跑出来的数据都一模一样，
 * 讲义里的所有数字都能复现。
 */

// [品牌, 分类, 产品名, 规格数组, 基准价, 标签, 卖点]
const LINES = [
  ['苹果', '手机', 'iPhone 15 Pro 钛金属', ['128G', '256G', '512G'], 7999, ['旗舰', '新品', '钛金属'], '搭载 A17 Pro 芯片，支持自适应高刷，影像系统强悍'],
  ['苹果', '手机', 'iPhone 15', ['128G', '256G'], 5999, ['新品', '轻薄'], 'A16 芯片日常流畅，机身轻薄手感好'],
  ['苹果', '笔记本', 'MacBook Air 13', ['8G+256G', '16G+512G'], 7999, ['轻薄', '长续航'], '无风扇静音设计，续航长达十八小时'],
  ['苹果', '平板', 'iPad Pro 11', ['128G', '256G'], 6499, ['旗舰', '高刷'], '支持手写笔悬停，是移动创作的生产力工具'],
  ['苹果', '耳机', 'AirPods Pro 2', ['标准版'], 1899, ['降噪', '热销'], '主动降噪明显升级，支持自适应通透模式'],
  ['苹果', '配件', '苹果 20W 快充充电器', ['标准版'], 149, ['热销'], '充电稳定不发烫，本商品不含数据线'],

  ['华为', '手机', 'Mate 60 Pro', ['256G', '512G'], 6999, ['旗舰', '新品'], '支持卫星通话，玄武机身抗摔耐用'],
  ['华为', '手机', 'nova 12', ['128G', '256G'], 2999, ['拍照', '轻薄'], '前置双摄自拍出色，机身轻薄好看'],
  ['华为', '笔记本', 'MateBook X Pro', ['16G+512G', '32G+1T'], 9999, ['轻薄', '高刷', '旗舰'], '触控全面屏，多屏协同提升办公效率'],
  ['华为', '平板', 'MatePad Pro 13', ['256G', '512G'], 5199, ['办公', '高刷'], '书写体验接近纸质，适合移动办公'],
  ['华为', '耳机', 'FreeBuds Pro 3', ['标准版'], 1499, ['降噪', '新品'], '智慧动态降噪，通话拾音清晰'],

  ['小米', '手机', '小米 14 Pro', ['256G', '512G'], 4999, ['旗舰', '新品'], '徕卡光学镜头，影像表现出色'],
  ['小米', '手机', 'Redmi K70', ['256G', '512G'], 2499, ['性价比', '热销'], '性能强劲价格厚道，游戏帧率稳定'],
  ['小米', '笔记本', '小米笔记本 Pro 14', ['16G+512G', '32G+1T'], 5299, ['办公', '高刷'], '高色域屏幕，适合编程与日常办公'],
  ['小米', '平板', '小米平板 6 Pro', ['128G', '256G'], 2599, ['性价比', '高刷'], '影音娱乐的好选择，性价比突出'],
  ['小米', '耳机', 'Xiaomi Buds 5 Pro', ['标准版'], 999, ['降噪', '性价比'], '降噪表现均衡，价格实惠'],
  ['小米', '配件', '小米 移动电源 20000mAh', ['标准版'], 199, ['性价比', '热销'], '大容量双口输出，本商品不含充电头'],

  ['联想', '笔记本', 'ThinkPad X1 Carbon', ['16G+512G', '32G+1T'], 11999, ['商务', '轻薄', '旗舰'], '键盘手感一流，商务出差首选机型'],
  ['联想', '笔记本', '小新 Pro 16', ['16G+1T'], 5499, ['办公', '高刷'], '大屏办公舒适，散热表现优秀'],
  ['联想', '配件', 'ThinkPad 雷电 4 扩展坞', ['标准版'], 799, ['商务', '办公'], '接口扩展丰富，本商品不含电源适配器'],

  ['戴尔', '笔记本', 'XPS 15', ['16G+512G', '32G+1T'], 12999, ['旗舰', '创作'], '屏幕色彩精准，视频创作者的最爱'],
  ['戴尔', '配件', '戴尔 27 寸 4K 显示器', ['2K', '4K'], 2199, ['办公', '创作'], '色彩准确接口齐全，本商品不含支架']
];

/** 线性同余伪随机：固定种子 → 任何人跑出来的数据完全一致 */
function makeRandom(seed = 20260902) {
  let state = seed;
  return () => {
    state = (state * 1103515245 + 12345) % 2147483648;
    return state / 2147483648;
  };
}

/**
 * 生成商品列表（原始账本）
 * @returns {Array} 约 40 条商品
 */
export function generateProducts() {
  const rand = makeRandom();
  const products = [];
  let seq = 0;

  for (const [brand, category, name, specs, basePrice, tags, highlight] of LINES) {
    for (let i = 0; i < specs.length; i++) {
      seq += 1;
      const spec = specs[i];
      // 规格越大越贵（同一产品线内递增约 12%）
      const price = Math.round(basePrice * (1 + 0.12 * i));
      const sales = 50 + Math.floor(rand() * 4000);
      const rating = Math.round((3.8 + rand() * 1.2) * 10) / 10;
      const listedAt = new Date(Date.UTC(2025, 0, 1) + Math.floor(rand() * 600) * 86400000)
        .toISOString()
        .slice(0, 10);

      products.push({
        sku: `SKU-${String(seq).padStart(4, '0')}`,
        title: `${brand} ${name} ${spec} ${category}`,
        brand,
        category,
        price,
        sales,
        rating,
        tags,
        description: `${highlight}。${brand}${name} ${spec} 版本，${category}品类中的${tags[0]}之选，适合日常${category === '配件' ? '搭配使用' : '工作与娱乐'}。`,
        on_sale: rand() > 0.3,
        listed_at: listedAt
      });
    }
  }

  return products;
}

/**
 * 故意造两条脏数据，用来验证「bulk 部分失败」的处理路径（课 12 实测结论）。
 *
 * 两条分别命中两类不可重试错误：
 * 1. price 写成字符串 → document_parsing_exception（类型解析失败）
 * 2. 多出一个映射里没有的字段 → strict_dynamic_mapping_exception（dynamic: strict 整篇拒收）
 */
export function dirtyProducts() {
  return [
    {
      sku: 'SKU-BAD-1',
      title: '测试 脏数据 价格非法 手机',
      brand: '测试',
      category: '手机',
      price: 'abc', // ← 应该是数字，这里故意写错
      sales: 1,
      rating: 1.0,
      tags: ['脏数据'],
      description: '这条文档的价格字段类型非法，用于验证 bulk 部分失败的处理',
      on_sale: false,
      listed_at: '2026-01-01'
    },
    {
      sku: 'SKU-BAD-2',
      title: '测试 脏数据 未知字段 手机',
      brand: '测试',
      category: '手机',
      price: 99,
      sales: 1,
      rating: 1.0,
      tags: ['脏数据'],
      description: '这条文档多了一个映射里没有的字段，用于验证 dynamic:strict 的整篇拒收',
      on_sale: false,
      listed_at: '2026-01-01',
      color: '红色' // ← 映射里没有这个字段，dynamic: strict 会整篇拒收
    }
  ];
}
