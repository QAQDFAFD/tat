import Foundation

/// Common Chinese names for clubs, keyed by ESPN `displayName`.
/// Anything missing falls back to ESPN's English short name.
enum TeamNames {
    static func localized(_ team: ESPNMatchProvider.Team) -> String {
        if let name = team.displayName, let chinese = table[name] { return chinese }
        return team.shortDisplayName ?? team.displayName ?? team.abbreviation ?? "?"
    }

    static let table: [String: String] = [
        // Premier League & recent Championship sides
        "Arsenal": "阿森纳", "Aston Villa": "阿斯顿维拉", "AFC Bournemouth": "伯恩茅斯", "Brentford": "布伦特福德",
        "Brighton & Hove Albion": "布莱顿", "Burnley": "伯恩利", "Chelsea": "切尔西", "Coventry City": "考文垂",
        "Crystal Palace": "水晶宫", "Everton": "埃弗顿", "Fulham": "富勒姆", "Hull City": "赫尔城",
        "Ipswich Town": "伊普斯维奇", "Leeds United": "利兹联", "Leicester City": "莱斯特城", "Liverpool": "利物浦",
        "Manchester City": "曼城", "Manchester United": "曼联", "Middlesbrough": "米德尔斯堡",
        "Newcastle United": "纽卡斯尔", "Norwich City": "诺维奇", "Nottingham Forest": "诺丁汉森林",
        "Sheffield United": "谢菲尔德联", "Southampton": "南安普顿", "Sunderland": "桑德兰",
        "Tottenham Hotspur": "热刺", "West Bromwich Albion": "西布朗", "West Ham United": "西汉姆联",
        "Wolverhampton Wanderers": "狼队",
        // La Liga
        "Real Madrid": "皇家马德里", "Barcelona": "巴塞罗那", "Atlético Madrid": "马德里竞技", "Athletic Club": "毕尔巴鄂竞技",
        "Real Sociedad": "皇家社会", "Real Betis": "皇家贝蒂斯", "Sevilla": "塞维利亚", "Valencia": "瓦伦西亚",
        "Villarreal": "比利亚雷亚尔", "Girona": "赫罗纳", "Celta Vigo": "塞尔塔", "Osasuna": "奥萨苏纳",
        "Getafe": "赫塔费", "Mallorca": "马略卡", "Rayo Vallecano": "巴列卡诺", "Espanyol": "西班牙人",
        // Serie A
        "Internazionale": "国际米兰", "AC Milan": "AC米兰", "Juventus": "尤文图斯", "Napoli": "那不勒斯",
        "AS Roma": "罗马", "Lazio": "拉齐奥", "Atalanta": "亚特兰大", "Fiorentina": "佛罗伦萨",
        "Bologna": "博洛尼亚", "Torino": "都灵", "Como": "科莫", "Genoa": "热那亚", "Udinese": "乌迪内斯",
        // Bundesliga
        "Bayern Munich": "拜仁慕尼黑", "Borussia Dortmund": "多特蒙德", "Bayer Leverkusen": "勒沃库森",
        "RB Leipzig": "莱比锡红牛", "Eintracht Frankfurt": "法兰克福", "VfB Stuttgart": "斯图加特",
        "VfL Wolfsburg": "沃尔夫斯堡", "Borussia Mönchengladbach": "门兴格拉德巴赫", "SC Freiburg": "弗赖堡",
        "Werder Bremen": "云达不莱梅", "Union Berlin": "柏林联合", "Hamburg SV": "汉堡",
        // Ligue 1
        "Paris Saint-Germain": "巴黎圣日耳曼", "Marseille": "马赛", "AS Monaco": "摩纳哥", "Lyon": "里昂",
        "Lille": "里尔", "Nice": "尼斯", "Lens": "朗斯", "Rennes": "雷恩",
        // Others often in the Champions League
        "Benfica": "本菲卡", "FC Porto": "波尔图", "Sporting CP": "葡萄牙体育", "Ajax Amsterdam": "阿贾克斯",
        "PSV Eindhoven": "埃因霍温", "Feyenoord Rotterdam": "费耶诺德", "Celtic": "凯尔特人", "Club Brugge": "布鲁日",
        "Galatasaray": "加拉塔萨雷",
        // NBA
        "Atlanta Hawks": "老鹰", "Boston Celtics": "凯尔特人", "Brooklyn Nets": "篮网", "Charlotte Hornets": "黄蜂",
        "Chicago Bulls": "公牛", "Cleveland Cavaliers": "骑士", "Dallas Mavericks": "独行侠", "Denver Nuggets": "掘金",
        "Detroit Pistons": "活塞", "Golden State Warriors": "勇士", "Houston Rockets": "火箭", "Indiana Pacers": "步行者",
        "LA Clippers": "快船", "Los Angeles Lakers": "湖人", "Memphis Grizzlies": "灰熊", "Miami Heat": "热火",
        "Milwaukee Bucks": "雄鹿", "Minnesota Timberwolves": "森林狼", "New Orleans Pelicans": "鹈鹕",
        "New York Knicks": "尼克斯", "Oklahoma City Thunder": "雷霆", "Orlando Magic": "魔术",
        "Philadelphia 76ers": "76人", "Phoenix Suns": "太阳", "Portland Trail Blazers": "开拓者",
        "Sacramento Kings": "国王", "San Antonio Spurs": "马刺", "Toronto Raptors": "猛龙", "Utah Jazz": "爵士",
        "Washington Wizards": "奇才",
    ]
}
