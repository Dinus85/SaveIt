// Classe per le FAQ
class FAQItem {
  final String question;
  final String answer;

  const FAQItem({required this.question, required this.answer});
}

// Costanti dell'applicazione
class AppConstants {
  // FAQ aggiornate per SaveIn
  static const List<FAQItem> faqItems = [
    FAQItem(
      question: 'Come posso salvare un link?',
      answer: 'Puoi salvare un link condividendolo direttamente nell\'app SaveIn da qualsiasi browser o social media. Usa il pulsante di condivisione e seleziona SaveIn dall\'elenco delle app.',
    ),
    FAQItem(
      question: 'Come funziona l\'organizzazione in cartelle?',
      answer: 'SaveIn ti permette di creare cartelle e sottocartelle (fino a 5 livelli: livello 0-4) per organizzare i tuoi contenuti. Usa il pulsante "+" nella home per creare nuove cartelle. Puoi spostare cartelle e post tramite il menu azioni.',
    ),
    FAQItem(
      question: 'Come funziona la ricerca?',
      answer: 'La ricerca di SaveIn cerca nei titoli delle cartelle e negli hashtag (#tag) dei tuoi post salvati. Puoi cercare per parole chiave o hashtag specifici per trovare rapidamente i contenuti.',
    ),
    FAQItem(
      question: 'Cosa sono gli hashtag e come li uso?',
      answer: 'Gli hashtag sono etichette che puoi aggiungere ai tuoi post per categorizzarli meglio. Ad esempio: #ricette, #viaggi, #tutorial. Usa il pulsante tag su ogni post per gestire gli hashtag.',
    ),
    FAQItem(
      question: 'Posso usare SaveIn offline?',
      answer: 'I contenuti già salvati sono accessibili offline per la visualizzazione, ma per aprire i link originali o salvarne di nuovi è necessaria una connessione internet.',
    ),
    FAQItem(
      question: 'Come cambio il tema dell\'app?',
      answer: 'Vai nella sezione Account > Impostazioni App e attiva/disattiva "Tema Scuro" per cambiare tra tema chiaro e scuro. Il cambio è immediato.',
    ),
    FAQItem(
      question: 'Come gestisco i consensi marketing?',
      answer: 'Puoi gestire tutti i consensi per le comunicazioni promozionali nella sezione Account > Impostazioni App. Troverai opzioni per email marketing e profilazione.',
    ),
    FAQItem(
      question: 'Quanti livelli di cartelle posso creare?',
      answer: 'SaveIn supporta fino a 5 livelli di cartelle annidate (livello 0 = cartelle principali, fino al livello 4 = sottocartelle più profonde). Questo limite aiuta a mantenere l\'organizzazione semplice e intuitiva.',
    ),
    FAQItem(
      question: 'Posso spostare cartelle e post?',
      answer: 'Sì! Usa il menu azioni (tre puntini) su cartelle e post per spostarli. Puoi spostare cartelle in altre cartelle o nella home, e post in qualsiasi cartella.',
    ),
    FAQItem(
      question: 'Come funzionano le statistiche?',
      answer: 'SaveIn traccia il tuo utilizzo per mostrarti statistiche interessanti: cartelle più usate, orari di utilizzo preferiti, streak di giorni consecutivi e molto altro. Vai in Account > Statistiche per vederle.',
    ),
    FAQItem(
      question: 'I miei dati sono al sicuro?',
      answer: 'Sì, SaveIn protegge i tuoi dati personali secondo la Privacy Policy. I dati di profilazione sono disciplinati dai Termini e Condizioni. Puoi sempre consultare entrambi i documenti dalla sezione Account.',
    ),
    FAQItem(
      question: 'Posso esportare i miei dati?',
      answer: 'Nelle statistiche trovi un\'opzione per esportare i tuoi dati analytics. Per i contenuti salvati, usa le funzioni di condivisione integrate nell\'app.',
    ),
  ];

  // Costanti tema
  static const String appName = 'SaveIn';
  static const String appVersion = '1.0.0';
  static const String buildDate = '2025.01.08';
  
  // ✅ FIX PRINCIPALE: Sistema livelli cartelle (5 livelli totali: 0, 1, 2, 3, 4)
  static const int maxFolderLevels = 4;        // Livello massimo raggiungibile (0-4)
  static const int totalFolderLevels = 5;      // Numero totale di livelli (0-4)
  static const int maxMessageLength = 250;

  // Helper method per controllo livelli
  static bool canHaveSubfolders(int currentLevel) {
    return currentLevel < maxFolderLevels;  // Livelli 0-2 possono avere figli
  }
  
  // Messaggi di errore standardizzati
  static String get maxLevelReachedMessage => 
    'Limite di $totalFolderLevels livelli raggiunto (livelli 0-$maxFolderLevels)';
  
  // Colori predefiniti per le cartelle
  static const List<String> folderColorNames = [
    'orange_200',
    'orange_100', 
    'pink_200',
    'purple_200',
    'blue_200',
    'green_200',
    'yellow_200',
    'red_200',
  ];
}