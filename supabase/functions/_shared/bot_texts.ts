// Everything the bot says, in the four launch languages.

export type Language = 'uz' | 'ru' | 'kk' | 'en';

export const languages: Language[] = ['uz', 'ru', 'kk', 'en'];

/** A supported language, defaulting to Russian (product spec §3). */
export function pickLanguage(code: string | null | undefined): Language {
  const short = (code ?? '').toLowerCase().slice(0, 2);
  return (languages as string[]).includes(short) ? (short as Language) : 'ru';
}

export interface BotTexts {
  /** Sent after "/start <token>", above the share button. */
  askContact: string;
  shareButton: string;
  done: string;
  ownNumberOnly: string;
  linkExpired: string;
  openApp: string;
}

export const botTexts: Record<Language, BotTexts> = {
  uz: {
    askContact:
      'Actra ilovasiga kirish uchun telefon raqamingizni yuboring.\n\n' +
      'Faqat kirishni oʻzingiz hozirgina ilovada boshlagan boʻlsangiz davom eting. ' +
      'Agar bu havolani sizga boshqa kishi yuborgan boʻlsa, raqamingizni yubormang.',
    shareButton: '📱 Telefon raqamimni yuborish',
    done: 'Tayyor! Actra ilovasiga qayting — siz tizimga kirdingiz.',
    ownNumberOnly: 'Iltimos, pastdagi tugma orqali oʻz raqamingizni yuboring. Boshqa kontakt qabul qilinmaydi.',
    linkExpired: 'Bu havola eskirgan. Actra ilovasida “Telegram orqali davom etish” tugmasini qayta bosing.',
    openApp: 'Bu Actra ilovasiga kirish boti. Ilovani oching va “Telegram orqali davom etish” tugmasini bosing.',
  },
  ru: {
    askContact:
      'Чтобы войти в Actra, отправьте свой номер телефона.\n\n' +
      'Продолжайте, только если вы сами только что начали вход в приложении. ' +
      'Если эту ссылку вам прислал кто-то другой, не отправляйте номер.',
    shareButton: '📱 Отправить мой номер',
    done: 'Готово! Вернитесь в приложение Actra — вы вошли.',
    ownNumberOnly: 'Пожалуйста, отправьте свой номер кнопкой ниже. Чужой контакт не подойдёт.',
    linkExpired: 'Эта ссылка устарела. Нажмите «Продолжить через Telegram» в приложении Actra ещё раз.',
    openApp: 'Это бот для входа в Actra. Откройте приложение и нажмите «Продолжить через Telegram».',
  },
  kk: {
    askContact:
      'Actra қолданбасына кіру үшін телефон нөміріңізді жіберіңіз.\n\n' +
      'Кіруді қолданбада дәл қазір өзіңіз бастаған болсаңыз ғана жалғастырыңыз. ' +
      'Бұл сілтемені сізге басқа адам жіберген болса, нөміріңізді жібермеңіз.',
    shareButton: '📱 Нөмірімді жіберу',
    done: 'Дайын! Actra қолданбасына оралыңыз — сіз жүйеге кірдіңіз.',
    ownNumberOnly: 'Өтінеміз, төмендегі түймені басып, өз нөміріңізді жіберіңіз. Басқа адамның контактісі қабылданбайды.',
    linkExpired: 'Бұл сілтеменің мерзімі өтті. Actra қолданбасында «Telegram арқылы жалғастыру» түймесін қайта басыңыз.',
    openApp: 'Бұл Actra қолданбасына кіруге арналған бот. Қолданбаны ашып, «Telegram арқылы жалғастыру» түймесін басыңыз.',
  },
  en: {
    askContact:
      'To sign in to Actra, share your phone number.\n\n' +
      'Continue only if you started this sign-in in the app yourself just now. ' +
      'If someone else sent you this link, do not share your number.',
    shareButton: '📱 Share my phone number',
    done: 'Done! Go back to the Actra app — you are signed in.',
    ownNumberOnly: 'Please share your own number with the button below. Another contact will not work.',
    linkExpired: 'This link has expired. Tap “Continue with Telegram” in the Actra app again.',
    openApp: 'This bot signs you in to Actra. Open the app and tap “Continue with Telegram”.',
  },
};
