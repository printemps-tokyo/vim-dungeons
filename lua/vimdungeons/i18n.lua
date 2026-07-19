-- Localization layer.
-- Japanese source strings are used as canonical keys; the English table
-- below translates them at display time. Missing keys fall back to Japanese.
-- Language is controlled by vim.g.vim_dungeons_lang ('en' | 'ja', default 'en').
local M = {}

local en = {
  -- Status line and UI chrome
  ['%s地下%d階  Lv:%d  HP:%d/%d  満腹度:%d  G:%d  ターン:%d  武:%s  盾:%s  腕:%s%s'] = '%sB%dF  Lv:%d  HP:%d/%d  Hunger:%d  G:%d  Turn:%d  Wpn:%s  Shd:%s  Brc:%s%s',
  ['【裏】'] = '[Abyss]',
  ['【日替】'] = '[Daily]',
  [' [毒]'] = ' [Poison]',
  [' [混乱]'] = ' [Confused]',
  [' == 持ち物 =='] = ' == Inventory ==',
  [' == 何を投げる？ =='] = ' == Throw what? ==',
  [' == 何を売る？ =='] = ' == Sell what? ==',
  [' == 何を置く？ =='] = ' == Drop what? ==',
  [' (何も持っていない)'] = ' (nothing held)',
  ['(攻+%d)'] = '(Atk+%d)',
  ['(守+%d)'] = '(Def+%d)',
  [' a-j:使う/装備する  q:閉じる'] = ' a-j: use/equip  q: close',
  [' a-j:売る  q:やめる'] = ' a-j: sell  q: cancel',
  [' a-j:置く  q:やめる'] = ' a-j: drop  q: cancel',
  [' a-j:選ぶ  q:やめる'] = ' a-j: choose  q: cancel',
  [' == メッセージ履歴 =='] = ' == Message log ==',
  [' q:閉じる'] = ' q: close',
  ['(呪)'] = '(cursed)',

  -- Help screen
  [' == 操作方法 =='] = ' == Controls ==',
  [' 【移動】'] = ' [Movement]',
  ['  h j k l / 矢印 :上下左右   y u b n :斜め'] = '  h j k l / arrows: move   y u b n: diagonals',
  ['  H J K L Y U B N:同方向へダッシュ(イベントで停止)'] = '  H J K L Y U B N: dash (stops on events)',
  ['  o :自動探索     . :その場で休む   > :階段を降りる'] = '  o: auto-explore   .: rest   >: descend stairs',
  [' 【アイテム】'] = ' [Items]',
  ['  i :持ち物(a-jで使用/装備)   t :投げる'] = '  i: inventory (a-j to use)   t: throw',
  ['  d :足元に置く               S :店で売る(店内)'] = '  d: drop at feet             S: sell (in shop)',
  [' 【情報】'] = ' [Info]',
  ['  M :メッセージ履歴   ? :このヘルプ   Q :中断して終了'] = '  M: message log   ?: this help   Q: suspend and quit',
  [' 敵にぶつかると攻撃。眠る敵への攻撃は不意打ち2倍。'] = ' Walk into enemies to attack. Sneak attacks deal x2.',
  [' HPは歩くと回復し、満腹度0でじわじわ減る。'] = ' HP regenerates as you walk; starving drains it.',
  [' 武器)盾]腕輪=は装備、草!巻物?杖/は使用、&が目標。'] = ' Equip )]=, use !?/, and reach the & to win.',
  [' 見えない罠^に注意。呪い装備は:w!の巻物で解呪。'] = ' Beware hidden traps ^. Uncurse gear with a :w! scroll.',
  [' 店Kの商品は精算制。dで棚に戻せる。'] = ' Shop K goods go on a tab; d puts them back.',

  -- Result screens
  ['     力尽きた…'] = '     You have fallen...',
  ['   ダンジョン踏破、おめでとう！'] = '   Dungeon conquered. Congratulations!',
  ['   裏ダンジョン踏破…完全制覇だ！'] = '   The Abyss is conquered... total mastery!',
  ['  Neovimの奥義書を手に入れた！'] = '  You obtained the Secrets of Neovim!',
  ['  Vimの聖典を手に入れた！'] = '  You obtained the Tome of Vim!',
  ['  死因: %s'] = '  Cause of death: %s',
  ['  記録: Lv%d / %dG / %dターン'] = '  Result: Lv%d / %dG / %d turns',
  ['  記録: 地下%d階 / Lv%d'] = '  Result: floor B%d / Lv%d',
  ['        %dG / %dターン'] = '        %dG / %d turns',
  ['  最高記録: 地下%d階%s'] = '  Best: B%dF%s',
  ['(踏破)'] = '(cleared)',
  ['  実績: %d/%d (:VimDungeonsAchievements)'] = '  Achievements: %d/%d (:VimDungeonsAchievements)',
  ['  r:もう一度  h:裏ダンジョンへ  q:やめる'] = '  r: retry  h: enter the Abyss  q: quit',
  ['  r:もう一度  q:やめる'] = '  r: retry  q: quit',

  -- Viewers
  [' == VimDungeons 実績 (%d/%d) =='] = ' == VimDungeons Achievements (%d/%d) ==',
  [' == VimDungeons 記録 =='] = ' == VimDungeons Records ==',
  [' == モンスター図鑑 (%d/%d) =='] = ' == Monster Codex (%d/%d) ==',
  [' %2d. %s地下%d階  Lv%d  %dG  %s  (%s)'] = ' %2d. %sB%dF  Lv%d  %dG  %s  (%s)',
  [' %s %s%s  HP%d 攻%d 防%d%s  撃破:%d'] = ' %s %s%s  HP%d Atk%d Def%d%s  Kills:%d',
  ['  %d-%d階'] = '  F%d-%d',
  [' ? ？？？'] = ' ? ???',
  [' まだ記録がない'] = ' No records yet',
  ['死因:'] = 'died to ',
  ['踏破！'] = 'cleared!',
  ['不明'] = 'unknown',
  ['倍速'] = 'double-speed',
  ['壁抜け'] = 'phasing',
  ['気まぐれ'] = 'erratic',

  -- Core game messages
  ['地下1階に足を踏み入れた。(?でヘルプ)'] = 'You step into floor B1. (? for help)',
  ['伝説のVimの聖典が地下%d階に眠っているという…'] = 'The legendary Tome of Vim sleeps on floor B%d...',
  ['裏ダンジョン『無限ヤンクの奈落』に足を踏み入れた…'] = 'You enter the Abyss of Infinite Yank...',
  ['Neovimの奥義書が地下%d階に眠るという。支給品はない'] = 'The Secrets of Neovim lie on floor B%d. No starting supplies.',
  ['地下%d階に降りた'] = 'You descend to floor B%d.',
  ['だだっ広い大広間のフロアだ'] = 'This floor is one vast hall.',
  ['入り組んだ迷路のフロアだ…'] = 'This floor is a twisting maze...',
  ['冒険を中断した。次回の:VimDungeonsで再開できる'] = 'Adventure suspended. Run :VimDungeons to resume.',
  ['冒険を再開した'] = 'Adventure resumed.',
  ['ここに階段はない'] = 'There are no stairs here.',
  ['階段だ。>で降りられる'] = 'Stairs. Press > to descend.',
  ['レベルが%dに上がった！'] = 'Welcome to level %d!',
  ['危険だ！HPが残りわずか…'] = 'Danger! Your HP is running out...',
  ['空腹で力が出ない…何か食べないと！'] = 'You are starving... you must eat something!',
  ['%dゴールドを手に入れた'] = 'You picked up %d gold.',
  ['%sを拾った'] = 'You picked up %s.',
  ['持ち物がいっぱいで%sを拾えない'] = 'Your pack is full; you cannot pick up %s.',
  ['持ち物がいっぱいで石を拾えない'] = 'Your pack is full; you cannot pick up the stones.',
  ['石を%d個拾った'] = 'You picked up %d stones.',
  ['石を%d個拾った(計%d個)'] = 'You picked up %d stones (total %d).',
  ['実績解除『%s』！'] = 'Achievement unlocked: %s!',
  ['%sが抜けた'] = 'The %s wears off.',
  ['毒が体を蝕んでいる…'] = 'Poison gnaws at your body...',
  ['体の異常もすっかり治った'] = 'All your ailments are cured too.',
  ['モンスターハウスだ！'] = 'A monster house!',
  ['探索し尽くした。ここが階段だ'] = 'Fully explored. These are the stairs.',
  ['これ以上進める場所がない'] = 'There is nowhere left to go.',
  ['敵から目を離せない'] = 'You cannot take your eyes off the enemy.',
  ['混乱していてまっすぐ歩けない'] = 'You are too confused to walk straight.',
  ['空気が張り詰めている…聖典の守護者の気配がする'] = 'The air is tense... the Tome guardian is near.',

  -- Combat
  ['%sを倒した！'] = 'You defeated the %s!',
  ['%sに%dのダメージ'] = 'The %s takes %d damage.',
  ['%sに攻撃をかわされた'] = 'The %s dodges your attack.',
  ['%sの攻撃をかわした'] = 'You dodge the %s.',
  ['%sから%dのダメージを受けた'] = 'The %s hits you for %d damage.',
  ['%sが目を覚ました！'] = 'The %s wakes up!',
  ['%sは金貨を落とした'] = 'The %s drops some gold.',
  ['不意打ち！'] = 'Sneak attack!',
  ['毒が体に回った！'] = 'Poison spreads through your body!',
  ['聖典を守る者はもういない…！'] = 'Nothing guards the Tome anymore...!',
  ['守護竜の炎のブレス！%dのダメージを受けた'] = "The guardian dragon's fire breath! You take %d damage.",

  -- Items
  ['%sは%sだった！'] = 'The %s was %s!',
  ['%sを飲んだ。HPが回復した'] = 'You drink the %s. HP restored.',
  ['%sを飲んだ。最大HPが1上がった'] = 'You drink the %s. Max HP +1.',
  ['%sを食べた。おなかがふくれた'] = 'You eat the %s. Your belly is full.',
  ['%sを読んだ。フロアの地形が頭に流れ込んだ！'] = 'You read the %s. The floor layout floods your mind!',
  ['%sを読んだ。視界の敵に裁きが下る！'] = 'You read the %s. Judgment falls on enemies in sight!',
  ['%sは消し去られた'] = 'The %s is erased.',
  ['しかし何も起きなかった'] = 'But nothing happened.',
  ['fの巻物: 跳び先の文字を入力(escで中止)'] = 'Scroll of f: type a target character (esc to cancel)',
  ['f%s: %sの眼前へ跳んだ！'] = 'f%s: you leap right in front of the %s!',
  ['f%s: 一気に跳んだ！'] = 'f%s: you leap across in one motion!',
  ['その文字は視界に見当たらない'] = 'No such character in sight.',
  ['やめておいた'] = 'You decide not to.',
  [':w! 保存完了。%sに強化された！'] = ':w! written. Upgraded to %s!',
  [':w! 呪いを上書き保存した！%sになった'] = ':w! overwrote the curse! It is now %s.',
  ['しかし何も装備していなかった…'] = 'But you have nothing equipped...',
  ['杖をどの方向に振る？(hjklyubn / escで中止)'] = 'Zap the wand which way? (hjklyubn / esc to cancel)',
  ['%sを装備した'] = 'You equip the %s.',
  ['%sを装備した(%sは持ち物に戻した)'] = 'You equip the %s (the %s goes back to your pack).',
  ['%sが呪われていて外せない！'] = 'The %s is cursed and cannot be removed!',
  ['なんと%sは呪われていた！外せない！'] = 'The %s was cursed! You cannot remove it!',
  ['%sを腕にはめた'] = 'You put the %s on your arm.',
  ['%sを腕にはめた(%sは外した)'] = 'You put on the %s (removed the %s).',
  ['石は投げて使うものだ(tで投げる)'] = 'Stones are for throwing (press t).',
  ['どの方向に投げる？(hjklyubn / escで中止)'] = 'Throw which way? (hjklyubn / esc to cancel)',
  ['%sを投げつけた！%sに%dのダメージ'] = 'You throw the %s! The %s takes %d damage.',
  ['%sを投げた。床に落ちた'] = 'You throw the %s. It lands on the floor.',
  ['%sは壁に当たって足元に落ちた'] = 'The %s hits the wall and drops at your feet.',
  ['稲妻が%sを撃った！20のダメージ'] = 'Lightning strikes the %s! 20 damage.',
  ['稲妻は壁に当たって消えた'] = 'The lightning hits a wall and fizzles.',
  ['%sと場所が入れ替わった！'] = 'You swap places with the %s!',
  ['魔法弾は壁に当たって消えた'] = 'The magic bolt hits a wall and fizzles.',
  ['%sは砕け散った'] = 'The %s shatters.',
  ['%sを足元に置いた'] = 'You drop the %s at your feet.',
  ['%sを棚に戻した'] = 'You put the %s back on the shelf.',
  ['足元には既に物がある'] = 'There is already something at your feet.',
  ['階段の上には置けない'] = 'You cannot drop things on the stairs.',
  ['投げられるものを持っていない'] = 'You have nothing to throw.',
  ['置けるものを持っていない'] = 'You have nothing to drop.',
  ['売れるものを持っていない'] = 'You have nothing to sell.',

  -- Shop
  ['%s(%dG)を手に取った。店を出る前に精算だ'] = 'You take the %s (%dG). Settle up before leaving.',
  ['店主「いらっしゃい。品物は店を出る前に精算だよ」'] = 'Keeper: "Welcome. Pay for goods before you leave."',
  ['店主「それはまだウチの商品だよ」'] = 'Keeper: "That is still my merchandise."',
  ['店主「泥棒だーっ！！」'] = 'Keeper: "THIEF!!"',
  ['店主「精算がまだだよ！」(所持金が足りない)'] = 'Keeper: "You have not paid!" (not enough gold)',
  ['店主に%dGを支払った。「まいどあり！」'] = 'You pay the keeper %dG. "Thank you kindly!"',
  ['%sを%dGで売った'] = 'You sell the %s for %dG.',
  ['ここでは売れない(店の中でSを押す)'] = 'You cannot sell here (press S inside a shop).',

  -- Traps
  ['とげの罠だ！%dのダメージを受けた'] = 'A spike trap! You take %d damage.',
  ['毒矢の罠だ！体に毒が回った'] = 'A poison dart trap! Poison spreads through you.',
  ['混乱の罠だ！足元がおぼつかない…'] = 'A confusion trap! Your feet feel unsteady...',
  ['大部屋の罠だ！壁が崩れ落ち、魔物たちが一斉に目を覚ました！'] = 'A big-room trap! The walls collapse and every monster wakes at once!',
  ['召喚の罠だ！魔物が湧き出した！'] = 'A summon trap! Monsters pour out!',
  ['ワープの罠だ！飛ばされた'] = 'A warp trap! You are whisked away.',
  ['落とし穴だ！地下%d階に落ちた'] = 'A pitfall! You drop to floor B%d.',
  ['毒消しの腕輪が毒を防いだ！'] = 'The Bracelet of Antidote blocks the poison!',

  -- Names: enemies
  ['スライム'] = 'Slime',
  ['コウモリ'] = 'Bat',
  ['ゴブリン'] = 'Goblin',
  ['毒ヘビ'] = 'Venom Snake',
  ['2jうさぎ'] = '2j Rabbit',
  ['ggゴースト'] = 'gg Ghost',
  ['オーク'] = 'Orc',
  ['ワイト'] = 'Wight',
  ['ドラゴン'] = 'Dragon',
  ['ダンジョンの店主'] = 'Dungeon Keeper',
  ['聖典の守護竜'] = 'Guardian Dragon of the Tome',

  -- Names: items
  ['薬草'] = 'Healing Herb',
  ['大きなパン'] = 'Big Bread',
  ['千里眼の巻物'] = 'Scroll of Clairvoyance',
  [':g//dの巻物'] = 'Scroll of :g//d',
  ['fの巻物'] = 'Scroll of f',
  [':w!の巻物'] = 'Scroll of :w!',
  ['いかずちの杖'] = 'Wand of Lightning',
  ['場所替えの杖'] = 'Wand of Swapping',
  ['こん棒'] = 'Club',
  ['銅の剣'] = 'Copper Sword',
  ['鋼鉄の剣'] = 'Steel Sword',
  ['皮の盾'] = 'Leather Shield',
  ['青銅の盾'] = 'Bronze Shield',
  ['ちからの腕輪'] = 'Bracelet of Power',
  ['毒消しの腕輪'] = 'Bracelet of Antidote',
  ['忍び足の腕輪'] = 'Bracelet of Sneaking',
  ['腹持ちの腕輪'] = 'Bracelet of Satiety',
  ['よくみえの腕輪'] = 'Bracelet of Insight',
  ['石'] = 'Stone',
  ['Vimの聖典'] = 'Tome of Vim',
  ['Neovimの奥義書'] = 'Secrets of Neovim',

  -- Names: unidentified appearances
  ['赤い草'] = 'Red Herb',
  ['青い草'] = 'Blue Herb',
  ['黄色い草'] = 'Yellow Herb',
  ['青い巻物'] = 'Blue Scroll',
  ['赤い巻物'] = 'Red Scroll',
  ['古びた巻物'] = 'Worn Scroll',
  ['光る巻物'] = 'Glowing Scroll',
  ['ひのきの杖'] = 'Cypress Wand',
  ['ねじれた杖'] = 'Twisted Wand',
  ['鉄の杖'] = 'Iron Wand',
  ['金の腕輪'] = 'Gold Bracelet',
  ['銀の腕輪'] = 'Silver Bracelet',
  ['銅の腕輪'] = 'Copper Bracelet',
  ['翡翠の腕輪'] = 'Jade Bracelet',
  ['黒曜石の腕輪'] = 'Obsidian Bracelet',

  -- Names: traps
  ['とげの罠'] = 'Spike Trap',
  ['毒矢の罠'] = 'Poison Dart Trap',
  ['混乱の罠'] = 'Confusion Trap',
  ['大部屋の罠'] = 'Big-Room Trap',
  ['召喚の罠'] = 'Summon Trap',
  ['ワープの罠'] = 'Warp Trap',
  ['落とし穴'] = 'Pitfall',

  -- Statuses / causes
  ['毒'] = 'poison',
  ['混乱'] = 'confusion',
  ['空腹'] = 'starvation',

  -- Achievements
  ['はじめての一撃'] = 'First Blood',
  ['敵を1体倒す'] = 'Defeat one enemy',
  ['中層探索者'] = 'Mid-Depth Explorer',
  ['地下5階に到達する'] = 'Reach floor B5',
  ['ベテラン冒険者'] = 'Veteran Adventurer',
  ['レベル10に到達する'] = 'Reach level 10',
  ['大金持ち'] = 'Deep Pockets',
  ['1000G以上を所持する'] = 'Hold 1000G or more',
  ['上客'] = 'Valued Customer',
  ['店で買い物をして精算する'] = 'Buy goods at a shop and pay up',
  ['武装商人返り討ち'] = 'Merchant Slayer',
  ['怒った店主を倒す'] = 'Defeat an angry shopkeeper',
  ['モンスターハウス生還'] = 'Monster House Survivor',
  ['モンスターハウスに遭遇した階から階段で生還する'] = 'Escape a monster-house floor by the stairs',
  ['竜殺し'] = 'Dragonslayer',
  ['聖典の守護竜を倒す'] = 'Defeat the Guardian Dragon of the Tome',
  ['真のVimmer'] = 'True Vimmer',
  ['裏ダンジョン『無限ヤンクの奈落』を踏破する'] = 'Conquer the Abyss of Infinite Yank',
  ['目利き'] = 'Appraiser',
  ['1回の冒険で全種の未識別アイテムを識別する'] = 'Identify every unidentified item type in one run',
  ['モンスター博士'] = 'Monster Scholar',
  ['図鑑を完成させる(全11種と遭遇)'] = 'Complete the codex (meet all 11 monsters)',
  ['深淵を覗くもの'] = 'Gazer into the Abyss',
  ['裏ダンジョンで地下15階に到達する'] = 'Reach floor B15 in the Abyss',
  ['ダンジョンを踏破する'] = 'Conquer the dungeon',
  ['Vimの聖典を手に入れた！ダンジョン踏破だ！'] = 'You obtained the Tome of Vim! The dungeon is conquered!',
}

function M.lang()
  local l = vim.g.vim_dungeons_lang
  if l == 'ja' then
    return 'ja'
  end
  return 'en'
end

function M.t(s)
  if s == nil then
    return s
  end
  if M.lang() == 'ja' then
    return s
  end
  return en[s] or s
end

-- Exposed for tests and tooling.
function M.set_dict(dict)
  en = dict
end

function M.dict()
  return en
end

return M
