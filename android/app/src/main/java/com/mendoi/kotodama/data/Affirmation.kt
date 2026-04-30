package com.mendoi.kotodama.data

data class Affirmation(
    val id: String,
    val text: String,
    val category: String,
    val customCategoryName: String? = null,
    val morningEnabled: Boolean = true,
    val eveningEnabled: Boolean = false,
    val orderIndex: Int = 0,
)

/// iOS と同じデフォルト 20件 seed
object DefaultAffirmations {
    val seed: List<Affirmation> = listOf(
        Affirmation("c1", "私は自分の人生を自分でデザインしている", "selfAffirm", "自信"),
        Affirmation("c2", "私は幸せを選んでいる", "selfAffirm", "自信"),
        Affirmation("c3", "私には夢を叶える力がある", "selfAffirm", "自信"),
        Affirmation("c4", "私は自分のベストバージョンに近づいている", "selfAffirm", "自信"),
        Affirmation("g1", "私はお金を簡単に、素早く引き寄せている", "goal", "豊かさ"),
        Affirmation("g2", "私は富を引き寄せる磁石だ", "goal", "豊かさ"),
        Affirmation("g3", "私は豊かさの中で生きている", "goal", "豊かさ"),
        Affirmation("g4", "私はより豊かになるチャンスに恵まれている", "goal", "豊かさ"),
        Affirmation("h1", "今日の私は、エネルギーに満ちあふれていて何でもできる", "habit", "生産性"),
        Affirmation("h2", "私は生産的に仕事をしている", "habit", "生産性"),
        Affirmation("h3", "私は計画を実行できている", "habit", "生産性"),
        Affirmation("h4", "私の頭の中も周りの環境もよく整理されていて、物事を着実に進めることができている", "habit", "生産性"),
        Affirmation("v1", "私は人の愛を受け入れて、人に愛を与えている", "values", "人間関係"),
        Affirmation("v2", "私は家族や友人といった素晴らしい人間関係に恵まれている", "values", "人間関係"),
        Affirmation("v3", "私は人を大切にするし、周りの人も私を大切にしてくれる", "values", "人間関係"),
        Affirmation("v4", "私は愛を受け入れる準備があるし、愛に値する人間だ", "values", "人間関係"),
        Affirmation("h5", "私は自分の体にいいものだけを、必要なときにだけ食べる", "values", "健康"),
        Affirmation("h6", "私は健康な体を持っている", "values", "健康"),
        Affirmation("h7", "私は理想通りの、健康で、強い体を持つ自分に近づいている", "values", "健康"),
        Affirmation("h8", "私は自分の体を愛し、尊敬している", "values", "健康"),
    )
}
