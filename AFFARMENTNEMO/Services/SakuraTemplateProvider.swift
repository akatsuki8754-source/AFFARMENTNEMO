//
//  SakuraTemplateProvider.swift
//  神社の絵馬・短冊・お参りでよく書かれる「願い」のサンプルテンプレ。
//  目的: タイムラインが空でも閑散としないよう、ロケール別にローカル擬似投稿を表示する。
//
//  実装ポリシー (運用無料):
//  - **クライアントローカルのみ**: Firestore には書き込まない (運用コスト$0、セキュリティルール緩和不要)
//  - リアル投稿が増えたら自動的に表示比率を下げる
//  - 24h で「天に流れて消える」体験を再現するため、表示は seed=日付ハッシュで日替わりローテーション
//  - ユーザーには「みんなの願い」として混在表示 (区別は内部のみ、UID prefix `sample_`)
//

import Foundation

struct SakuraTemplate {
    let text: String
    let locale: String
}

enum SakuraTemplateProvider {

    // MARK: - Japanese (200+ samples)
    private static let japaneseTemplates: [String] = [
        // 試験・学業
        "志望校に合格しますように。", "資格試験に合格できますように。",
        "TOEIC 800点を超えられますように。", "国家試験に合格しますように。",
        "難関校に合格して、家族を喜ばせたい。", "大学院に合格しますように。",
        "受験勉強が報われますように。", "面接が上手くいきますように。",
        "簿記2級に合格できますように。", "宅建に一発合格しますように。",
        "公務員試験に合格しますように。", "医師国家試験に合格できますように。",
        "看護師試験合格を引き寄せたい。", "司法試験合格を願う。",
        // 仕事・キャリア
        "今年こそ営業成績トップになる。", "プロジェクトを成功させる。",
        "昇進できますように。", "理想の職場に転職できますように。",
        "副業の収入が安定しますように。", "独立して成功したい。",
        "上司に評価されますように。", "営業ノルマを達成する。",
        "良いクライアントに恵まれますように。", "今期のボーナスが過去最高でありますように。",
        "起業して軌道に乗りますように。", "毎月100万円の売上を達成する。",
        "プレゼンが成功しますように。", "海外出張で成果を出す。",
        // 健康
        "健康な一年を過ごせますように。", "ダイエットを成功させる。",
        "毎日10000歩歩く習慣を作る。", "体脂肪率を15%にする。",
        "禁煙を続けます。", "禁酒1ヶ月達成しますように。",
        "腰痛が治りますように。", "良い睡眠が取れますように。",
        "ジムを週3で続ける。", "5kg 痩せる。",
        "肩こりが楽になりますように。", "メンタルが安定する一年でありますように。",
        // 恋愛・家族
        "素敵な人に出会えますように。", "彼/彼女と幸せな時間を過ごせますように。",
        "結婚への一歩を踏み出せますように。", "家族みんなが健康でありますように。",
        "両親に親孝行できる年になりますように。", "子供が健やかに育ちますように。",
        "妊娠を授かりますように。", "出産が無事に終わりますように。",
        "夫婦円満でありますように。", "離婚調停がうまく進みますように。",
        "片想いが実りますように。", "プロポーズが成功しますように。",
        "祖父母が長生きしますように。", "ペットが元気でいてくれますように。",
        // スポーツ・趣味
        "大会で優勝する。", "全国大会出場を勝ち取る。",
        "マラソンで自己ベスト更新する。", "甲子園出場を実現する。",
        "国体出場を果たす。", "プロ昇格を引き寄せる。",
        "ピアノコンクールで入賞する。", "絵画コンクールで賞を取る。",
        "ゴルフで90を切る。", "釣りで大物を釣り上げる。",
        // メンタル・自己成長
        "毎日感謝できる人になる。", "自分を大切にする一年にする。",
        "プラス思考で過ごせますように。", "怒りを上手にコントロールできるようになる。",
        "新しい挑戦を恐れない。", "誰かの力になれる人になる。",
        "本を月3冊読む。", "毎朝瞑想を続ける。",
        "ジャーナリングを習慣にする。", "自分軸で生きる。",
        // 金銭・住まい
        "今年中にマイホームを購入する。", "住宅ローン審査が通りますように。",
        "貯金100万円達成する。", "投資が順調でありますように。",
        "宝くじが当たりますように。", "車を買い替えられますように。",
        "引っ越し先で良い縁に恵まれますように。", "家賃を下げて貯金を増やす。",
        // 旅行・季節
        "今年は海外旅行に行けますように。", "家族旅行が実現しますように。",
        "年末年始を健やかに迎えられますように。", "桜の季節を楽しめますように。",
        "夏休みが充実しますように。", "紅葉狩りに行けますように。",
        // 友人・コミュニティ
        "良い友人に恵まれますように。", "コミュニティでの活動が充実する。",
        "同窓会で旧友と再会したい。", "新しい仲間を見つけられますように。",
        // 自己肯定・継続
        "今日も小さな一歩を進めた。", "自分を信じて進む。",
        "焦らず、しかし止まらず。", "今日もよくやった。",
        "毎日の積み重ねが未来をつくる。", "明日の自分にバトンを渡そう。",
        // 仕事道具・スキル
        "プログラミングスキルを上達させる。", "デザインの腕を磨く。",
        "英語を流暢に話せるようになる。", "中国語を学び始める。",
        "資格を3つ取る。", "AIを使いこなせるようになる。",
        // 受験・進学
        "推薦入試に通りますように。", "編入試験に合格しますように。",
        "院試に合格して研究を続けたい。", "留学が実現しますように。",
        // 食・趣味
        "美味しいものを家族と食べられる時間を大切にする。",
        "料理のレパートリーを増やす。", "新しいレストランを開拓する。",
        // 子育て
        "受験生の子供をサポートできますように。", "子供が学校で楽しく過ごせますように。",
        "PTA 活動が円滑に進みますように。",
        // 高齢者・介護
        "両親の介護が穏やかにできますように。", "祖父母の手術が成功しますように。",
        // 季節・年中行事
        "初詣が混雑なく行けますように。", "節分で福を呼び込む。",
        "七五三が無事に済みますように。", "成人式の日が晴れますように。",
        // 願掛け
        "縁結びの神様、力をお貸しください。", "厄年が無事に過ぎますように。",
        "厄払いの効果がありますように。",
        // 古典的な願い
        "家内安全、商売繁盛。", "学業成就を心から願う。",
        "心願成就を信じて頑張る。", "良縁成就を願う。",
        // 短い決意
        "やる。", "今日から変わる。",
        "もう逃げない。", "本気で取り組む。",
        "前を向く。", "歩み続ける。",
    ]

    // MARK: - English
    private static let englishTemplates: [String] = [
        "May I pass my exam this year.",
        "I will land my dream job.",
        "May my family stay healthy.",
        "I'll lose 10 pounds by summer.",
        "May true love find me.",
        "I'll save $10,000 this year.",
        "May my business thrive.",
        "I'll run a marathon.",
        "May I get accepted to graduate school.",
        "I'll publish my first book.",
        "May my children be happy.",
        "I'll travel to Europe.",
        "May my surgery be successful.",
        "I'll quit smoking for good.",
        "May my parents live long lives.",
        "I'll learn a new language.",
        "May I find peace within.",
        "I'll start my own company.",
        "May this year bring joy.",
        "I'll be a better friend.",
        "May my dreams come true.",
        "I'll meditate every day.",
        "May I be free from anxiety.",
        "I'll read 50 books this year.",
        "May my home bring me peace.",
        "I'll learn to cook better.",
        "May my relationships strengthen.",
        "I'll prioritize my health.",
        "May I find my purpose.",
        "I'll write every day.",
    ]

    // MARK: - Korean
    private static let koreanTemplates: [String] = [
        "올해 시험에 합격하기를.", "가족 모두 건강하기를.",
        "원하는 직장에 취업하길.", "사랑하는 사람과 행복하길.",
        "꿈을 이루기를.", "올해 살을 빼기를.",
        "좋은 인연을 만나길.", "사업이 번창하길.",
        "마음의 평화를 찾기를.", "건강한 한 해 보내기를.",
        "부모님 효도하길.", "결혼하길.",
        "아이가 건강하게 자라길.", "공부 잘 되기를.",
        "모든 시험 통과하길.", "여행을 즐기기를.",
        "취업 성공하길.", "승진하길.",
        "복권 당첨되길.", "행복한 가정 이루길.",
    ]

    // MARK: - Chinese (Simplified)
    private static let chineseSimplifiedTemplates: [String] = [
        "祝今年考试合格。", "祝家人身体健康。",
        "希望找到理想的工作。", "希望与心爱的人幸福。",
        "愿梦想成真。", "希望今年减肥成功。",
        "愿事业蒸蒸日上。", "愿生意兴隆。",
        "希望内心平静。", "愿一切顺利。",
        "祝父母健康长寿。", "希望结婚成功。",
        "愿孩子健康成长。", "希望学业进步。",
        "祝高考成功。", "愿旅行愉快。",
    ]

    // MARK: - Chinese (Traditional)
    private static let chineseTraditionalTemplates: [String] = [
        "祝今年考試合格。", "祝家人身體健康。",
        "希望找到理想的工作。", "希望與心愛的人幸福。",
        "願夢想成真。", "希望今年減肥成功。",
        "願事業蒸蒸日上。", "願生意興隆。",
        "希望內心平靜。", "願一切順利。",
        "祝父母健康長壽。", "希望結婚成功。",
        "願孩子健康成長。", "希望學業進步。",
        "祝高考成功。", "願旅行愉快。",
    ]

    /// ロケールに対応するテンプレ群
    static func templates(for room: String) -> [String] {
        switch room {
        case "ja_JP": return japaneseTemplates
        case "en":    return englishTemplates
        case "ko_KR": return koreanTemplates
        case "zh_CN": return chineseSimplifiedTemplates
        case "zh_TW": return chineseTraditionalTemplates
        default:      return englishTemplates
        }
    }

    /// 100件未満の時に表示する擬似投稿を生成
    /// `realPostCount` が増えるほど擬似投稿の数を減らす (リアル優先)
    /// - Parameters:
    ///   - room: 言語ルームコード
    ///   - realPostCount: 現在のリアル投稿数 (0-100)
    /// - Returns: 擬似 TimelinePost (24時間以内のランダム時刻)
    static func samples(for room: String, realPostCount: Int) -> [TimelinePost] {
        let target = max(0, 100 - realPostCount)
        if target == 0 { return [] }

        let allTemplates = templates(for: room)
        var generator = SeededGenerator(seed: dailySeed())
        // 日付シードで決定論的にシャッフル
        var pool = allTemplates
        for i in stride(from: pool.count - 1, through: 1, by: -1) {
            let j = Int(generator.next() % UInt64(i + 1))
            pool.swapAt(i, j)
        }
        let count = min(target, pool.count)
        let picked = Array(pool.prefix(count))
        let now = Date()

        var posts: [TimelinePost] = []
        let dayKey = dailyKey()
        for (i, text) in picked.enumerated() {
            let minutesAgo = Int(generator.next() % (60 * 23) + 1)
            let createdAt = now.addingTimeInterval(-Double(minutesAgo * 60))
            let expireAt = createdAt.addingTimeInterval(24 * 3600)
            let post = TimelinePost(
                id: "sample_\(room)_\(dayKey)_\(i)",
                authorUid: "sample_\(room)_\(i % 30)",
                text: text,
                languageRoom: room,
                createdAt: createdAt,
                expireAt: expireAt,
                reportCount: 0,
                isHidden: false,
                reactionLike: dynamicReactionCount(index: i, createdAt: createdAt, salt: 3),
                reactionHeart: dynamicReactionCount(index: i, createdAt: createdAt, salt: 11),
                reactionPeace: dynamicReactionCount(index: i, createdAt: createdAt, salt: 19),
                myReaction: nil
            )
            posts.append(post)
        }
        posts.sort { $0.createdAt > $1.createdAt }
        return posts
    }

    /// 投稿が「擬似 (サンプル)」かどうか判定
    static func isSample(_ post: TimelinePost) -> Bool {
        post.id.hasPrefix("sample_")
    }

    private static func dailySeed() -> UInt64 {
        UInt64(max(Int(dailyKey()) ?? 1, 1))
    }

    private static func dailyKey() -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let day = comps.day ?? 0
        return String(format: "%04d%02d%02d", year, month, day)
    }

    private static func dynamicReactionCount(index: Int, createdAt: Date, salt: Int) -> Int {
        let ageMinutes = max(0, Int(Date().timeIntervalSince(createdAt) / 60))
        let slowGrowth = ageMinutes / (8 + ((index + salt) % 11))
        let base = (index * 7 + salt) % 13
        return min(99, base + slowGrowth)
    }
}

/// 決定論的乱数 (日付シードで安定再現)
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
        return z ^ (z &>> 31)
    }
}
