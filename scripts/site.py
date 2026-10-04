#!/usr/bin/env python3
"""Renders docs/, the GitHub Pages site: two landing pages (en, ru), the five articles in both
languages straight from Sources/MGF/Resources, a sitemap, and the social preview image.
usage: scripts/site.py [--no-social]   (social.png needs Google Chrome)"""
import html, pathlib, re, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / 'docs'
RES = ROOT / 'Sources/MGF/Resources'
BASE = 'https://been-earth.github.io/mac-gaming-fixes/'
REPO = 'https://github.com/been-earth/mac-gaming-fixes'
VERSION = re.search(r'CFBundleShortVersionString</key><string>([^<]+)', (ROOT / 'scripts/Info.plist').read_text()).group(1)
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

SLUGS = ['registry-save-deferral', 'low-latency-wifi', 'audio-buffer-fix', 'function-keys', 'audio-devices']
ICONS = dict(zip(SLUGS, ['save-off', 'wifi', 'audio-lines', 'keyboard', 'headphones']))
FIXES, TOOLS = SLUGS[:3], SLUGS[3:]

# MARK: copy

T = {
'en': dict(
    lang='en', other='ru', other_label='по-русски', home='', dir='en',
    title='MacGamingFixes: fix stutter, net jitter and crackling audio in CrossOver games on Mac',
    description='Free macOS app for Apple silicon that fixes the stutter every 30 seconds, net jitter on Wi-Fi, crackling sound and a choppy mic in CS2, Deadlock and other Windows games running in CrossOver. Plus F1–F12 without Fn and quick audio device switching.',
    h1='windows games in crossover on a mac. no <em>stutter</em>, no <em>net jitter</em>, no <em>crackling sound</em>.',
    lead='cs2, deadlock or any other windows game through crossover brings three problems no game or macos setting fixes: the game hitches every 30 seconds, wi-fi shows constant net jitter, the sound crackles and your mic cuts out in voice chat. macgamingfixes is a small, free macos app that removes all three by patching crossover\'s wine. every fix is a switch; switching it off restores the original files.',
    download=f'download {VERSION} · dmg', source='source on github',
    facts='apple silicon · macos 14+ · crossover 26 · mit license · english and russian',
    nav=[('#fixes', 'fixes'), ('#faq', 'is this my problem?'), ('#install', 'install')],
    fixes_h='three fixes inside crossover', fixes_p='measured on one macbook pro m3 max with crossover 26.0 and deadlock. every card opens the article with the method and the figures.',
    before='before', after='after', how='how it works',
    tools_h='two tools for macos', tools_p='they change ordinary macos settings, nothing inside crossover, and take effect at once.',
    faq_h='is this my problem?',
    install_h='install', steps=[
        f'download <code>MacGamingFixes-{VERSION}.dmg</code> from <a href="{REPO}/releases/latest">releases</a> and open it.',
        'drag macgamingfixes into applications.',
        'allow the first launch: the build is not signed by apple, see below.',
        'open the app. the setup takes a minute: language, where crossover is, one macos permission, which fixes to apply.',
        'restart whatever runs in the bottle: steam, or the game started from crossover. anything already running keeps the old files, and the app names what to restart after every apply.'],
    update_h='after a crossover update', update_p='a crossover update, or a cxpatcher re-patch, replaces the patched files, so the fixes are gone until applied again. open macgamingfixes once after updating: by default it notices and puts the fixes back; with that off, it warns and leaves the switches to you.',
    gate_h='the first launch: not signed by apple', gate_p='there is no apple developer certificate behind this project, so macos stops the app once and says it could not verify it. either open <b>system settings → privacy &amp; security</b>, scroll to the message about macgamingfixes and press <b>open anyway</b>, or remove the download flag in terminal:',
    gate_note='no admin password, no sip changes, no full disk access. the one permission the setup asks for is app management, so the app may write inside crossover.',
    foot=f'made by ilia novikov · <a href="mailto:contact@been.earth">contact@been.earth</a> · <a href="{REPO}/issues">issues</a> · <a href="{REPO}/blob/main/LICENSE">mit license</a> · not affiliated with codeweavers, valve or apple.',
    article_meta='part of macgamingfixes. the same article is in the app, next to the switch.', back='all fixes', cta='download macgamingfixes',
    faq=[
        ('cs2 or deadlock stutters every 30 seconds on mac (crossover, steam)',
         'steady fps, then a hitch like clockwork every 30 seconds, and the net graph or the deadlock telemetry shows a jitter spike at the same moment. that is wine\'s registry save, not your network or gpu: the wine server rewrites <code>system.reg</code> (12 mb in a steam bottle) and every process in the bottle waits about 240 ms. lower graphics settings change nothing; <a href="en/registry-save-deferral.html">registry save deferral</a> removes the stall.'),
        ('high net jitter or packet loss in cs2 on mac over wi-fi',
         'two different things. jitter that shows up only on the mac, with a connection that is otherwise fine, is usually the wi-fi chip\'s power saving: it holds packets for up to 25 ms unless a socket asks for real-time service, which native games do and wine does not. <a href="en/low-latency-wifi.html">low-latency wi-fi</a> fixes that part. packet loss measured past your router (the provider, the game relay) is not on your mac and nothing here changes it; <code>ping</code> your router and then a relay to tell the two apart. playing on battery adds spikes of 100 ms and more on top of everything: plug the charger in.'),
        ('crackling, popping audio in crossover games; mic cuts out in discord or voice chat',
         'the usual advice is to set the output device to 96 khz in audio midi setup. it works because at 96 khz coreaudio\'s 512-frame block is shorter than wine\'s 10 ms audio period. bluetooth headsets and most usb microphones cannot run at 96 khz, so at 44.1 or 48 khz playback gets silence inserted and the microphone loses about 7 % of what you say. <a href="en/audio-buffer-fix.html">audio buffer fix</a> asks coreaudio for the short block at any sample rate, so the 96 khz device is no longer needed. a separate trap: when macos picks a bluetooth headset\'s own microphone as the input, the headset drops to 16 khz mono; the <a href="en/audio-devices.html">audio devices</a> tool warns about it.'),
        ('f1–f12 do not work in games on a macbook without fn',
         'macos has the switch (keyboard → "use f1, f2, etc. keys as standard function keys"), buried and manual. <a href="en/function-keys.html">function keys</a> flips it at once: by hand, or automatically while the game you pick is running or macos game mode is on.'),
        ('does it work with whisky, game porting toolkit, parallels, or native steam games?',
         'not yet. the app patches the crossover bundle only (tested with crossover 26). whisky and game porting toolkit lay their wine out the same way but ship an older wine (7.7 against crossover\'s 11), so at least the audio wrapper would need its own build. parallels is a virtual machine, not wine. native mac games (dota 2, for one) never had these problems. if you want whisky support, <a href="' + REPO + '/issues">open an issue</a> or write to contact@been.earth.'),
        ('which games and which macs?',
         'the fixes act on the bottle, not on a game: everything in the same crossover bottle gets them, and the steam bottle usually holds all your games. measured with deadlock; cs2 runs in the same bottle. one machine so far: macbook pro m3 max, macos 27, crossover 26.0. apple silicon only.'),
    ],
),
'ru': dict(
    lang='ru', other='en', other_label='in english', home='../', dir='ru',
    title='MacGamingFixes: лаги, net jitter и треск звука в играх через CrossOver на Mac',
    description='Бесплатное приложение для macOS на Apple silicon: убирает лаги каждые 30 секунд, net jitter по Wi-Fi, треск звука и заикающийся микрофон в CS2, Deadlock и других Windows-играх через CrossOver. Плюс F1–F12 без Fn и быстрый выбор аудиоустройств.',
    h1='windows-игры в crossover на mac. без <em>лагов</em>, без <em>net jitter</em>, без <em>треска звука</em>.',
    lead='cs2, deadlock и любая другая windows-игра через crossover приносят три проблемы, которые не лечатся ни настройками игры, ни настройками macos: игра дёргается каждые 30 секунд, по wi-fi постоянный net jitter, звук трещит, а микрофон заикается в голосовом чате. macgamingfixes — маленькое бесплатное приложение для macos, которое убирает все три патчем wine внутри crossover. каждый фикс — переключатель; выключили — оригинальные файлы вернулись на место.',
    download=f'скачать {VERSION} · dmg', source='исходники на github',
    facts='apple silicon · macos 14+ · crossover 26 · лицензия mit · русский и английский',
    nav=[('#fixes', 'фиксы'), ('#faq', 'это про меня?'), ('#install', 'установка')],
    fixes_h='три фикса внутри crossover', fixes_p='замерено на одном macbook pro m3 max с crossover 26.0 и deadlock. каждая карточка открывает статью с методом и цифрами.',
    before='до', after='после', how='как это работает',
    tools_h='два инструмента для macos', tools_p='они меняют обычные настройки macos, а не crossover, и действуют сразу.',
    faq_h='это про меня?',
    install_h='установка', steps=[
        f'скачайте <code>MacGamingFixes-{VERSION}.dmg</code> из <a href="{REPO}/releases/latest">релизов</a> и откройте.',
        'перетащите macgamingfixes в «программы».',
        'разрешите первый запуск: сборка не подписана apple, см. ниже.',
        'откройте приложение. настройка занимает минуту: язык, где лежит crossover, одно разрешение macos, какие фиксы применить.',
        'перезапустите то, что работает в бутылке: steam или игру, запущенную из crossover. уже запущенное использует старые файлы, и приложение после каждого применения называет, что перезапустить.'],
    update_h='после обновления crossover', update_p='обновление crossover или повторный патч cxpatcher заменяют пропатченные файлы, так что фиксы слетают, пока их не применить заново. откройте macgamingfixes один раз после обновления: по умолчанию он это заметит и вернёт фиксы сам; если автоповтор выключен — предупредит и оставит переключатели вам.',
    gate_h='первый запуск: без подписи apple', gate_p='за проектом нет сертификата разработчика apple, поэтому macos один раз остановит приложение и скажет, что не может его проверить. либо откройте <b>системные настройки → конфиденциальность и безопасность</b>, найдите сообщение про macgamingfixes и нажмите <b>всё равно открыть</b>, либо снимите флаг загрузки в терминале:',
    gate_note='без пароля администратора, без отключения sip, без полного доступа к диску. единственное разрешение, которое просит настройка, — «управление приложениями», чтобы приложение могло писать внутрь crossover.',
    foot=f'автор — илья новиков · <a href="mailto:contact@been.earth">contact@been.earth</a> · <a href="{REPO}/issues">issues</a> · <a href="{REPO}/blob/main/LICENSE">лицензия mit</a> · не связано с codeweavers, valve и apple.',
    article_meta='часть macgamingfixes. та же статья есть в приложении, рядом с переключателем.', back='все фиксы', cta='скачать macgamingfixes',
    faq=[
        ('cs2 или deadlock лагает каждые 30 секунд на mac (crossover, steam)',
         'ровный fps, а потом рывок как по часам каждые 30 секунд, и график сети или телеметрия deadlock в тот же момент показывает всплеск джиттера. это запись реестра wine, а не сеть и не видеокарта: сервер wine переписывает <code>system.reg</code> (12 мб в бутылке steam), и каждый процесс бутылки ждёт около 240 мс. снижение графики не помогает; <a href="registry-save-deferral.html">отсрочка записи реестра</a> убирает фриз.'),
        ('высокий net jitter или потери пакетов в cs2 на mac по wi-fi',
         'это две разные вещи. джиттер, который виден только на mac при в целом нормальном соединении, — обычно энергосбережение чипа wi-fi: он придерживает пакеты до 25 мс, пока какой-нибудь сокет не попросит класс реального времени; нативные игры просят, wine — нет. <a href="low-latency-wifi.html">wi-fi без задержек</a> чинит эту часть. потери пакетов за роутером (провайдер, игровой релей) к mac не относятся, и здесь их ничто не исправит; чтобы отличить одно от другого, сделайте <code>ping</code> до роутера, а потом до релея. игра от батареи добавляет сверху всплески по 100 мс и больше: подключите зарядку.'),
        ('треск и щелчки звука в играх через crossover; микрофон заикается в discord или голосовом чате',
         'обычный совет — выставить устройству вывода 96 кгц в audio midi setup. он работает потому, что на 96 кгц блок coreaudio в 512 кадров короче 10-мс аудиопериода wine. bluetooth-гарнитуры и большинство usb-микрофонов 96 кгц не умеют, поэтому на 44.1 и 48 кгц в воспроизведение вставляется тишина, а микрофон теряет около 7 % сказанного. <a href="audio-buffer-fix.html">фикс аудиобуфера</a> просит у coreaudio короткий блок на любой частоте, и устройство на 96 кгц больше не нужно. отдельная ловушка: когда macos выбирает входом микрофон самой bluetooth-гарнитуры, она переходит в 16 кгц моно; инструмент <a href="audio-devices.html">аудиоустройства</a> об этом предупреждает.'),
        ('f1–f12 не работают в играх на macbook без fn',
         'в macos есть этот переключатель (клавиатура → «использовать клавиши f1, f2 и др. как стандартные функциональные»), но он спрятан и ручной. <a href="function-keys.html">функциональные клавиши</a> переключают его сразу: вручную или автоматически, пока запущена выбранная игра или включён игровой режим macos.'),
        ('работает ли с whisky, game porting toolkit, parallels и нативными играми steam?',
         'пока нет. приложение патчит только пакет crossover (проверено на crossover 26). у whisky и game porting toolkit та же раскладка wine, но версия старее (7.7 против 11 в crossover), так что как минимум аудио-обёртке нужна своя сборка. parallels — виртуальная машина, не wine. у нативных mac-игр (например, dota 2) этих проблем никогда не было. нужна поддержка whisky — <a href="' + REPO + '/issues">откройте issue</a> или напишите на contact@been.earth.'),
        ('какие игры и какие mac?',
         'фиксы действуют на бутылку, а не на игру: их получает всё в той же бутылке crossover, а бутылка steam обычно содержит все ваши игры. замерено с deadlock; cs2 работает в той же бутылке. пока одна машина: macbook pro m3 max, macos 27, crossover 26.0. только apple silicon.'),
    ],
),
}

CSS = """
/* the bundled Red Hat Mono is Latin only: Cyrillic comes from Menlo (macOS) or Consolas (Windows) */
@font-face { font-family: "Red Hat Mono"; font-weight: 300 700; src: url("ASSETS/RedHatMono.ttf"); font-display: swap; }
:root { --page: #070b09; --card: #101813; --panel: #0c120e; --line: #1a251d; --line-strong: #28382d; --text: #e6efe8; --text-2: #a9b8ad; --muted: #7a8b7e; --accent: #39ff6e; --accent-dim: #1f6b38; --warning: #ffbd2e; }
* { box-sizing: border-box; }
html { background: var(--page); scroll-behavior: smooth; }
body { margin: 0; font: 400 15px/1.6 "Red Hat Mono", Menlo, Consolas, monospace; color: var(--text-2); -webkit-font-smoothing: antialiased; }
a { color: var(--accent); text-decoration: none; } a:hover { text-decoration: underline; }
code { font: inherit; font-size: 0.93em; padding: 1px 5px; border-radius: 4px; background: var(--card); border: 1px solid var(--line); color: var(--text); }
pre { margin: 0; padding: 14px 16px; overflow-x: auto; font: 400 13px/1.55 "Red Hat Mono", Menlo, Consolas, monospace; color: var(--text); }
pre code { padding: 0; border: 0; background: none; font-size: inherit; }
.wrap { max-width: 1040px; margin: 0 auto; padding: 0 16px; }
header.top { position: sticky; top: 0; z-index: 2; background: rgba(7, 11, 9, .92); backdrop-filter: blur(8px); border-bottom: 1px solid var(--line); }
header.top .wrap { display: flex; align-items: center; gap: 20px; height: 56px; }
.brand { display: flex; align-items: center; gap: 10px; color: var(--text); font-weight: 500; letter-spacing: -0.02em; }
.brand img { width: 28px; height: 28px; border-radius: 7px; }
nav { display: flex; gap: 18px; margin-left: auto; font-size: 13px; }
nav a { color: var(--text-2); } nav a.gh { color: var(--text); }
h1 { margin: 0; font: 500 clamp(26px, 3.4vw, 40px)/1.2 "Red Hat Mono", Menlo, Consolas, monospace; letter-spacing: -0.03em; color: var(--text); max-width: 900px; }
h1 em { font-style: normal; color: var(--accent); white-space: nowrap; }
h2 { margin: 0 0 8px; font: 500 clamp(22px, 2.4vw, 28px)/1.25 "Red Hat Mono", Menlo, Consolas, monospace; letter-spacing: -0.03em; color: var(--text); }
h3 { margin: 28px 0 8px; font: 500 17px/1.4 "Red Hat Mono", Menlo, Consolas, monospace; color: var(--text); }
section { padding: 56px 0; border-top: 1px solid var(--line); } section.hero { border: 0; padding: 72px 0 56px; }
.lead { max-width: 820px; margin: 20px 0 28px; font-size: 16px; }
.sub { margin: 0 0 28px; color: var(--muted); max-width: 820px; }
.btns { display: flex; flex-wrap: wrap; gap: 10px; }
.btn { display: inline-flex; align-items: center; gap: 8px; padding: 11px 16px; border-radius: 6px; font-size: 14px; font-weight: 500; border: 1px solid var(--line-strong); color: var(--text); background: var(--card); }
.btn:hover { text-decoration: none; border-color: var(--accent-dim); }
.btn.primary { background: var(--accent); border-color: var(--accent); color: #06130a; } .btn.primary:hover { filter: brightness(1.08); }
.btn svg { width: 16px; height: 16px; }
.facts { margin: 18px 0 0; font-size: 13px; color: var(--muted); }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-top: 24px; } .grid.two { grid-template-columns: repeat(2, 1fr); }
.card { display: flex; flex-direction: column; gap: 12px; padding: 18px; border: 1px solid var(--line); border-radius: 8px; background: var(--card); }
.card .t { display: flex; align-items: center; gap: 10px; color: var(--text); font-weight: 500; font-size: 16px; }
.card .t svg { width: 20px; height: 20px; color: var(--accent); flex: none; }
.card .use { color: var(--text); } .card .mech { font-size: 13px; color: var(--muted); }
.card .more { margin-top: auto; font-size: 13px; }
.bars { display: grid; grid-template-columns: auto 1fr auto; gap: 6px 10px; align-items: center; font-size: 12px; padding-top: 12px; border-top: 1px solid var(--line); }
.bars .l { grid-column: 1 / -1; color: var(--muted); letter-spacing: .06em; text-transform: uppercase; font-size: 11px; }
.bars i { display: block; height: 8px; border-radius: 2px; } .bars i.b { background: var(--warning); } .bars i.a { background: var(--accent); }
.bars b { font-weight: 500; color: var(--text); white-space: nowrap; }
.faq p { max-width: 820px; margin: 0; }
ol.steps { margin: 20px 0 0; padding-left: 22px; max-width: 820px; } ol.steps li { margin: 8px 0; padding-left: 4px; }
.note { max-width: 820px; } .note p { margin: 8px 0; }
figure.code { margin: 16px 0; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); overflow: hidden; max-width: 820px; }
figure.code figcaption { padding: 6px 16px; border-bottom: 1px solid var(--line); font-size: 12px; color: var(--muted); }
aside.warn, aside.note-box { margin: 16px 0; padding: 12px 14px; border-left: 2px solid var(--warning); background: var(--card); border-radius: 0 6px 6px 0; max-width: 820px; }
aside.warn::before { content: "[WARN] "; color: var(--warning); }
footer.bottom { padding: 32px 0 48px; border-top: 1px solid var(--line); font-size: 13px; color: var(--muted); }
article { max-width: 820px; padding: 48px 0; } article h1 { font-size: clamp(26px, 3vw, 34px); } article .meta { margin: 8px 0 32px; font-size: 13px; color: var(--muted); }
article h2 { margin: 36px 0 10px; font-size: 20px; } article p { margin: 10px 0; } article ul { padding-left: 22px; } article li { margin: 4px 0; }
article table { border-collapse: collapse; margin: 16px 0; font-size: 13px; width: 100%; max-width: 820px; }
article th, article td { text-align: left; padding: 7px 10px; border-bottom: 1px solid var(--line); vertical-align: top; } article th { color: var(--muted); font-weight: 500; }
article .bars { max-width: 480px; margin: 16px 0; padding: 12px 14px; border: 1px solid var(--line); border-radius: 6px; background: var(--card); }
.crumbs { font-size: 13px; color: var(--muted); margin-bottom: 24px; } .crumbs a { color: var(--text-2); }
.cta { margin-top: 40px; padding-top: 24px; border-top: 1px solid var(--line); display: flex; flex-wrap: wrap; gap: 10px; align-items: center; }
@media (max-width: 860px) { .grid, .grid.two { grid-template-columns: 1fr; } nav .hide { display: none; } section { padding: 40px 0; } section.hero { padding: 48px 0 40px; } }
"""

# MARK: markdown subset the articles use: #, ##, paragraphs, - lists, tables, ``` fences (sh, c, bars), > quotes

def inline(s):
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', html.escape(s, quote=False))

def bars(t, label, unit, before, after):
    width = max(2.0, min(100.0, after / before * 100)) if before else 100.0
    unit = (' ' + unit) if unit != '%' else ' %'
    def num(x): return f'{x:g}'
    return (f'<div class="bars"><span class="l">{html.escape(label)}</span>'
            f'<span>{t["before"]}</span><i class="b" style="width:100%"></i><b>{num(before)}{unit}</b>'
            f'<span>{t["after"]}</span><i class="a" style="width:{width:.1f}%"></i><b>{num(after)}{unit}</b></div>')

def render(md, t):
    lines, out, i, title = md.split('\n'), [], 0, ''
    block = re.compile(r'(#|```|\||- |> )')
    while i < len(lines):
        l = lines[i]
        if l.startswith('```'):
            info = l[3:].strip().split(None, 1)
            lang, cap = (info[0] if info else ''), (info[1] if len(info) > 1 else '')
            body, i = [], i + 1
            while i < len(lines) and not lines[i].startswith('```'): body.append(lines[i]); i += 1
            i += 1
            if lang == 'bars':
                for b in body:
                    label, unit, before, after = [x.strip() for x in b.split('|')]
                    out.append(bars(t, label, unit, float(before), float(after)))
            else:
                out.append('<figure class="code">' + (f'<figcaption>{html.escape(cap)}</figcaption>' if cap else '')
                           + f'<pre><code>{html.escape(chr(10).join(body))}</code></pre></figure>')
        elif l.startswith('# '): title = l[2:].strip(); i += 1
        elif l.startswith('## '):
            text = l[3:].strip(); out.append(f'<h2 id="{re.sub(r"[^a-z0-9а-я]+", "-", text.lower()).strip("-")}">{inline(text)}</h2>'); i += 1
        elif l.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(set(c) <= set('-: ') for c in cells): rows.append(cells)
                i += 1
            head, body = rows[0], rows[1:]
            out.append('<table><thead><tr>' + ''.join(f'<th>{inline(c)}</th>' for c in head) + '</tr></thead><tbody>'
                       + ''.join('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in r) + '</tr>' for r in body) + '</tbody></table>')
        elif l.startswith('- '):
            items = []
            while i < len(lines) and lines[i].startswith('- '): items.append(lines[i][2:]); i += 1
            out.append('<ul>' + ''.join(f'<li>{inline(x)}</li>' for x in items) + '</ul>')
        elif l.startswith('>'):
            q = []
            while i < len(lines) and lines[i].startswith('>'): q.append(lines[i][1:].strip()); i += 1
            warn = bool(q) and q[0].startswith('[!')
            out.append(f'<aside class="{"warn" if warn else "note-box"}">{inline(" ".join(q[1:] if warn else q))}</aside>')
        elif not l.strip(): i += 1
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not block.match(lines[i]): para.append(lines[i].strip()); i += 1
            out.append(f'<p>{inline(" ".join(para))}</p>')
    return title, '\n'.join(out)

def article_parts(slug, lang):
    """title, first paragraph, measure (label, unit, before, after) or None"""
    md = (RES / f'{lang}.lproj/{slug}.md').read_text()
    title = re.search(r'^# (.+)$', md, re.M).group(1).strip()
    first = next(p.strip() for p in md.split('\n\n')[1:] if p.strip() and not p.startswith('#'))
    m = re.search(r'^```bars\n(.+?)\n', md, re.M)
    measure = [x.strip() for x in m.group(1).split('|')] if m else None
    return title, first, measure

# MARK: pages

def icon(name):
    svg = (RES / f'Icons/{name}.svg').read_text()
    return re.sub(r'<\?xml[^>]*>|<!--.*?-->', '', svg, flags=re.S).strip()

def page(t, path, title, description, body, kind):
    depth = path.count('/')
    up = '../' * depth
    url = BASE + path.replace('index.html', '')  # the same form as the sitemap: canonical and sitemap must agree
    other = {'index.html': 'ru/index.html', 'ru/index.html': 'index.html'}.get(path) or (('ru/' if t['lang'] == 'en' else 'en/') + path.split('/')[-1])
    alt = {t['lang']: url, t['other']: BASE + other.replace('index.html', '')}
    ld = ''
    if kind == 'home':
        faq = [{'@type': 'Question', 'name': q, 'acceptedAnswer': {'@type': 'Answer', 'text': re.sub(r'<[^>]+>', '', a)}} for q, a in t['faq']]
        import json
        ld = '<script type="application/ld+json">' + json.dumps([
            {'@context': 'https://schema.org', '@type': 'SoftwareApplication', 'name': 'MacGamingFixes', 'operatingSystem': 'macOS 14 or later, Apple silicon',
             'applicationCategory': 'UtilitiesApplication', 'softwareVersion': VERSION, 'license': REPO + '/blob/main/LICENSE', 'url': BASE,
             'downloadUrl': REPO + '/releases/latest', 'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'}, 'description': t['description'],
             'author': {'@type': 'Person', 'name': 'Ilia Novikov', 'email': 'contact@been.earth'}},
            {'@context': 'https://schema.org', '@type': 'FAQPage', 'mainEntity': faq}], ensure_ascii=False) + '</script>'
    nav = ''.join(f'<a class="hide" href="{up if kind != "home" else ""}{h}">{l}</a>' for h, l in t['nav']) if kind == 'home' else f'<a class="hide" href="{up}{"" if t["lang"] == "en" else "ru/"}">{t["back"]}</a>'
    return f'''<!doctype html>
<html lang="{t['lang']}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(description)}">
<link rel="canonical" href="{url}">
<link rel="alternate" hreflang="en" href="{alt['en']}">
<link rel="alternate" hreflang="ru" href="{alt['ru']}">
<link rel="alternate" hreflang="x-default" href="{alt['en']}">
<link rel="icon" href="{up}icon.png">
<meta property="og:type" content="website">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(description)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{BASE}social.png">
<meta property="og:image:width" content="2560"><meta property="og:image:height" content="1280">
<meta name="twitter:card" content="summary_large_image">
<style>{CSS.replace('ASSETS/', up + 'assets/')}</style>
{ld}
</head>
<body>
<header class="top"><div class="wrap">
  <a class="brand" href="{up}{'' if t['lang'] == 'en' else 'ru/'}"><img src="{up}icon.png" alt="">MacGamingFixes</a>
  <nav>{nav}<a href="{up}{other}" hreflang="{t['other']}">{t['other_label']}</a><a class="gh" href="{REPO}">github ↗</a></nav>
</div></header>
<main class="wrap">
{body}
</main>
<footer class="bottom"><div class="wrap">{t['foot']}</div></footer>
</body>
</html>
'''

def home(t):
    lang = t['lang']
    cards = []
    for slug in FIXES:
        title, first, m = article_parts(slug, lang)
        label, unit, before, after = m
        cards.append(f'<div class="card"><div class="t">{icon(ICONS[slug])}{html.escape(title)}</div><p class="use">{inline(first)}</p>'
                     + bars(t, label, unit, float(before), float(after)) + f'<a class="more" href="{lang}/{slug}.html">{t["how"]} →</a></div>')
    tools = []
    for slug in TOOLS:
        title, first, _ = article_parts(slug, lang)
        tools.append(f'<div class="card"><div class="t">{icon(ICONS[slug])}{html.escape(title)}</div><p class="use">{inline(first)}</p>'
                     f'<a class="more" href="{lang}/{slug}.html">{t["how"]} →</a></div>')
    faq = ''.join(f'<h3>{q}</h3><p>{a}</p>' for q, a in t['faq'])
    steps = ''.join(f'<li>{s}</li>' for s in t['steps'])
    body = f'''<section class="hero">
  <h1>{t['h1']}</h1>
  <p class="lead">{t['lead']}</p>
  <div class="btns"><a class="btn primary" href="{REPO}/releases/latest">{icon('arrow-right')}{t['download']}</a><a class="btn" href="{REPO}">{icon('git-fork')}{t['source']}</a></div>
  <p class="facts">{t['facts']}</p>
</section>
<section id="fixes"><h2>{t['fixes_h']}</h2><p class="sub">{t['fixes_p']}</p><div class="grid">{''.join(cards)}</div></section>
<section id="faq" class="faq"><h2>{t['faq_h']}</h2>{faq}</section>
<section id="tools"><h2>{t['tools_h']}</h2><p class="sub">{t['tools_p']}</p><div class="grid two">{''.join(tools)}</div></section>
<section id="install"><h2>{t['install_h']}</h2><ol class="steps">{steps}</ol>
  <h3>{t['update_h']}</h3><div class="note"><p>{t['update_p']}</p></div>
  <h3>{t['gate_h']}</h3><div class="note"><p>{t['gate_p']}</p>
  <figure class="code"><pre><code>xattr -dr com.apple.quarantine /Applications/MacGamingFixes.app</code></pre></figure>
  <p>{t['gate_note']}</p></div>
</section>'''
    return page(t, 'index.html' if lang == 'en' else 'ru/index.html', t['title'], t['description'], body, 'home')

def article(slug, t):
    lang = t['lang']
    title, body = render((RES / f'{lang}.lproj/{slug}.md').read_text(), t)
    _, first, _ = article_parts(slug, lang)
    home_href = '../' if lang == 'en' else './'
    nav_home = '../' if lang == 'en' else '../ru/'
    desc = re.sub(r'`', '', first)
    if len(desc) > 160: desc = desc[:157].rsplit(' ', 1)[0] + '…'
    content = f'''<article>
<div class="crumbs"><a href="{nav_home}">macgamingfixes</a> / {html.escape(title)}</div>
<h1>{html.escape(title)}</h1>
<p class="meta">{t['article_meta']}</p>
{body}
<div class="cta"><a class="btn primary" href="{REPO}/releases/latest">{icon('arrow-right')}{t['cta']}</a><a class="btn" href="{nav_home}">{t['back']}</a></div>
</article>'''
    return page(t, f'{lang}/{slug}.html', f'{title} · MacGamingFixes', desc, content, 'article')

def social():
    """1280×640 at 2x, for the GitHub social preview and og:image."""
    (DOCS / 'social.html').write_text(f'''<!doctype html>
<!-- the social preview: scripts/site.py renders it to social.png with headless chrome at 2x -->
<html lang="en"><meta charset="utf-8"><title>MacGamingFixes</title>
<style>
@font-face {{ font-family: "Red Hat Mono"; font-weight: 300 700; src: url("assets/RedHatMono.ttf"); }}
:root {{ --page: #070b09; --card: #101813; --line: #1a251d; --text: #e6efe8; --text-2: #a9b8ad; --muted: #7a8b7e; --accent: #39ff6e; --warning: #ffbd2e; }}
html, body {{ margin: 0; background: var(--page); }}
body {{ width: 1280px; height: 640px; box-sizing: border-box; padding: 56px 72px; display: flex; flex-direction: column; justify-content: space-between;
       font: 400 16px/1.5 "Red Hat Mono", monospace; color: var(--text-2); -webkit-font-smoothing: antialiased; position: relative; overflow: hidden; }}
body::before {{ content: ""; position: absolute; right: -200px; top: -260px; width: 720px; height: 720px; border-radius: 50%; background: radial-gradient(closest-side, rgba(57, 255, 110, .10), transparent); }}
header {{ display: flex; align-items: center; gap: 16px; color: var(--text); font-size: 22px; font-weight: 500; letter-spacing: -0.02em; }}
header img {{ width: 48px; height: 48px; border-radius: 12px; }}
header span {{ color: var(--muted); font-weight: 400; font-size: 16px; margin-left: 8px; }}
h1 {{ margin: 0; font: 500 52px/1.15 "Red Hat Mono", monospace; letter-spacing: -0.035em; color: var(--text); max-width: 1040px; }}
h1 b {{ font-weight: inherit; color: var(--accent); white-space: nowrap; }}
p {{ margin: 18px 0 0; font-size: 19px; max-width: 980px; }}
ul {{ margin: 0; padding: 0; list-style: none; display: flex; gap: 14px; }}
li {{ padding: 12px 16px; border: 1px solid var(--line); border-radius: 8px; background: var(--card); font-size: 14px; color: var(--muted); }}
li strong {{ display: block; font: 500 24px/1.2 "Red Hat Mono", monospace; color: var(--text); margin-bottom: 2px; }}
li i {{ font-style: normal; color: var(--warning); }} li em {{ font-style: normal; color: var(--accent); }}
</style>
<header><img src="icon.png" alt="">MacGamingFixes<span>// crossover · apple silicon · free</span></header>
<div><h1>windows games on a mac. no <b>stutter</b>, no <b>net jitter</b>, no <b>crackling sound</b>.</h1>
<p>fixes for cs2, deadlock and other windows games in crossover: the hitch every 30 seconds, late wi-fi packets, crackling audio and a choppy mic.</p></div>
<ul><li><strong><i>264 ms</i> → <em>10 ms</em></strong>the freeze every 30 seconds</li><li><strong><i>8.7 ms</i> → <em>3.8 ms</em></strong>latency to the router on wi-fi</li><li><strong><i>6.3 %</i> → <em>0.1 %</em></strong>silence cut into game audio</li></ul>
</html>
''')
    if '--no-social' in sys.argv or not pathlib.Path(CHROME).exists(): return print('social.png: skipped (no chrome)')
    subprocess.run([CHROME, '--headless=new', '--hide-scrollbars', '--allow-file-access-from-files', '--window-size=1280,640', '--force-device-scale-factor=2',
                    f'--screenshot={DOCS / "social.png"}', str(DOCS / 'social.html')], check=True, capture_output=True)
    print(f'social.png: {(DOCS / "social.png").stat().st_size // 1024} kb')

def main():
    assets = DOCS / 'assets'; assets.mkdir(parents=True, exist_ok=True)
    for name in ['RedHatMono.ttf', 'OFL.txt']: shutil.copy(RES / 'Fonts' / name, assets / name)
    (DOCS / '.nojekyll').write_text('')
    pages = []
    for lang, t in T.items():
        path = 'index.html' if lang == 'en' else 'ru/index.html'
        (DOCS / path).parent.mkdir(exist_ok=True)
        (DOCS / path).write_text(home(t)); pages.append(path)
        (DOCS / lang).mkdir(exist_ok=True)
        for slug in SLUGS:
            (DOCS / lang / f'{slug}.html').write_text(article(slug, t)); pages.append(f'{lang}/{slug}.html')
    (DOCS / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
                                      + ''.join(f'  <url><loc>{BASE}{p.replace("index.html", "")}</loc></url>\n' for p in pages) + '</urlset>\n')
    (DOCS / 'robots.txt').write_text(f'User-agent: *\nAllow: /\nSitemap: {BASE}sitemap.xml\n')
    social()
    print(f'{len(pages)} pages in docs/')

if __name__ == '__main__':
    main()
