MGF · Mac Gaming Fixes · вариант 1c

MGF.icns            — готовая иконка приложения (16–1024, 1x/2x)
MGF.iconset/        — те же PNG под iconutil; файлы *-2x.png переименовать в *@2x.png, затем: iconutil -c icns MGF.iconset
png/                — иконка по размерам 16 / 32 / 64 / 128 / 256 / 512 / 1024
menubar/            — template-иконка строки меню 23×18, @1x и @2x (чёрный + альфа; в Xcode: Render As → Template Image)
wordmark/           — MGF + плитка-ключ, прозрачный фон, @2x и @4x
svg/                — исходники; текст набран Red Hat Mono 600 (OFL), шрифт должен быть установлен или перевести в кривые

цвета: фон #101813 · кант #28382d · буквы #e6efe8 · акцент #39ff6e
