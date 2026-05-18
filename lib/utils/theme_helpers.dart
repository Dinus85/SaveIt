import 'package:flutter/material.dart';

// Helper class per la gestione dei temi
class ThemeHelpers {
  
  // Colori del tema scuro - AGGIORNATI
  static const Color darkBackgroundColor = Color(0xFF1E3A8A); // Blu scuro
  static const Color darkCardColor = Color(0xFF424242); // Colors.grey[800]
  static const Color darkTextColor = Colors.white;
  static const Color darkTitleColor = Colors.black; // ← AGGIUNTO: Titoli neri nel tema scuro
  static final Color darkSubtitleColor = const Color.fromARGB(255, 129, 129, 133);
  static final Color darkFieldColor = Colors.grey.shade800;
  static final Color darkHintColor = Colors.grey.shade400;
  
  // Colori del tema chiaro - AGGIORNATI
  static const Color lightBackgroundColor = Color(0xFFE0F2FE); // Azzurro chiaro
  static const Color lightCardColor = Colors.white;
  static const Color lightTextColor = Color(0xFF212121); // Colors.black87
  static final Color lightSubtitleColor = Colors.black87;
  static final Color lightFieldColor = Colors.grey.shade100;
  static final Color lightHintColor = Colors.grey.shade600;

  // Ottiene il colore di sfondo in base al tema
  static Color getBackgroundColor(bool isDarkTheme) {
    return isDarkTheme ? darkBackgroundColor : lightBackgroundColor;
  }

  // Ottiene il colore delle card in base al tema
  static Color getCardColor(bool isDarkTheme) {
    return isDarkTheme ? darkCardColor : lightCardColor;
  }

  // Ottiene il colore del testo principale in base al tema
  static Color getTextColor(bool isDarkTheme) {
    return isDarkTheme ? darkTextColor : lightTextColor;
  }

  // ← AGGIUNTO: Ottiene il colore dei titoli in base al tema
  static Color getTitleColor(bool isDarkTheme) {
    return isDarkTheme ? darkTitleColor : lightTextColor; // Nel tema scuro: nero, nel tema chiaro: stesso del testo normale
  }

  // ← AGGIUNTO: Ottiene il colore delle icone in base al tema
  static Color getIconColor(bool isDarkTheme) {
    return isDarkTheme ? darkTitleColor : lightTextColor; // Same come i titoli - nero nel tema scuro
  }

  // Ottiene il colore del testo secondario in base al tema
  static Color getSubtitleColor(bool isDarkTheme) {
    return isDarkTheme ? darkSubtitleColor : lightSubtitleColor;
  }

  // Ottiene il colore dei campi di input in base al tema
  static Color getFieldColor(bool isDarkTheme) {
    return isDarkTheme ? darkFieldColor : lightFieldColor;
  }

  // Ottiene il colore dei hint in base al tema
  static Color getHintColor(bool isDarkTheme) {
    return isDarkTheme ? darkHintColor : lightHintColor;
  }

  // Crea il ThemeData per il tema scuro
  static ThemeData createDarkTheme() {
    return ThemeData(
      primarySwatch: Colors.blue,
      scaffoldBackgroundColor: darkBackgroundColor,
      brightness: Brightness.dark,
      cardColor: darkCardColor,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: darkTextColor),
        bodyMedium: TextStyle(color: darkTextColor),
        titleLarge: TextStyle(color: darkTextColor),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackgroundColor,
        foregroundColor: darkTextColor,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  // Crea il ThemeData per il tema chiaro
  static ThemeData createLightTheme() {
    return ThemeData(
      primarySwatch: Colors.blue,
      scaffoldBackgroundColor: lightBackgroundColor,
      brightness: Brightness.light,
      cardColor: lightCardColor,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: lightTextColor),
        bodyMedium: TextStyle(color: lightTextColor),
        titleLarge: TextStyle(color: lightTextColor),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBackgroundColor,
        foregroundColor: lightTextColor,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  // Ottiene tutti i colori del tema in un oggetto COMPLETO
  static ThemeColors getThemeColors(bool isDarkTheme) {
    return ThemeColors(
      backgroundColor: getBackgroundColor(isDarkTheme),
      cardColor: getCardColor(isDarkTheme),
      textColor: getTextColor(isDarkTheme),
      titleColor: getTitleColor(isDarkTheme), // ← AGGIUNTO
      iconColor: getIconColor(isDarkTheme), // ← AGGIUNTO
      subtitleColor: getSubtitleColor(isDarkTheme),
      fieldColor: getFieldColor(isDarkTheme),
      hintColor: getHintColor(isDarkTheme),
      mainBackgroundColor: getMainBackgroundColor(isDarkTheme),
      bottomBarColor: getBottomBarColor(isDarkTheme),
    );
  }

  // FUNZIONI SPECIFICHE PER COLORI PERSONALIZZATI
  
  // Ottiene il colore di sfondo principale (diverso da backgroundColor per le card)
  static Color getMainBackgroundColor(bool isDarkTheme) {
    return isDarkTheme ? Color.fromARGB(255, 212, 255, 236) : Color.fromARGB(255, 187, 227, 253); // Blu scuro / Azzurro chiaro
  }
  
  // Ottiene il colore della barra di navigazione
  static Color getBottomBarColor(bool isDarkTheme) {
    return isDarkTheme ? Color.fromARGB(255, 36, 99, 72) : Color.fromARGB(255, 103, 186, 230); // Blu molto scuro / Azzurro più scuro
  }
  
  // FUNZIONE UNIFICATA: Ottiene tutti i colori personalizzati
  static Map<String, Color> getCustomColors(bool isDarkTheme) {
    return {
      'backgroundColor': getMainBackgroundColor(isDarkTheme),
      'bottomBarColor': getBottomBarColor(isDarkTheme),
    };
  }

  // ← AGGIUNTO: Metodo per aggiornare automaticamente il tema dell'app
  static void updateAppTheme(BuildContext context, bool isDark) {
    // Trova il MaterialApp più vicino e forza il rebuild
    final materialApp = context.findAncestorWidgetOfExactType<MaterialApp>();
    if (materialApp != null) {
      // Forza un hot reload del tema
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          // Notifica il cambio tema al sistema
          (context as Element).markNeedsBuild();
        }
      });
    }
  }

  // ← AGGIUNTO: Forza il rebuild globale dell'app (Soluzione 2)
  static void forceGlobalRebuild(BuildContext context) {
    print('DEBUG: Forzando rebuild globale dell\'app...');
    
    // 1. Trova l'elemento root dell'app e forza il suo rebuild
    try {
      final rootElement = context.findRootAncestorStateOfType<State>();
      if (rootElement != null && rootElement.mounted) {
        print('DEBUG: Trovato root element, forzando setState...');
        rootElement.setState(() {
          // Forza il rebuild di tutto l'albero dall'app root
        });
      }
    } catch (e) {
      print('DEBUG: Errore nel rebuild del root element: $e');
    }
    
    // 2. Forza il rebuild di tutti gli elementi nella navigazione
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        print('DEBUG: Forzando rebuild di tutti gli elementi...');
        try {
          // Marca tutti gli elementi come "dirty" per forzare il rebuild
          void markElementDirty(Element element) {
            element.markNeedsBuild();
            element.visitChildren(markElementDirty);
          }
          
          // Inizia dal context corrente e visita tutti gli ancestor
          Element currentElement = context as Element;
          markElementDirty(currentElement);
          
          // Visita tutti gli elementi ancestor
          currentElement.visitAncestorElements((element) {
            markElementDirty(element);
            return true; // Continua la visita
          });
          
          print('DEBUG: Rebuild globale completato');
        } catch (e) {
          print('DEBUG: Errore nel rebuild degli elementi: $e');
        }
      }
    });
    
    // 3. Forza un ulteriore rebuild dopo un breve delay per garantire l'aggiornamento
    Future.delayed(Duration(milliseconds: 50), () {
      if (context.mounted) {
        try {
          (context as Element).markNeedsBuild();
          print('DEBUG: Rebuild finale eseguito');
        } catch (e) {
          print('DEBUG: Errore nel rebuild finale: $e');
        }
      }
    });
  }

  // Stile per il titolo principale dell'app
  static TextStyle getAppTitleStyle(bool isDarkTheme) {
    return TextStyle(
      color: getTitleColor(isDarkTheme), // ← MODIFICATO: Usa getTitleColor invece di getTextColor
      fontSize: 32,
      fontWeight: FontWeight.bold,
    );
  }

  // Stile per i titoli delle sezioni
  static TextStyle getSectionTitleStyle(bool isDarkTheme) {
    return TextStyle(
      color: getTitleColor(isDarkTheme), // ← MODIFICATO: Usa getTitleColor invece di getTextColor
      fontSize: 20,
      fontWeight: FontWeight.bold,
    );
  }

  // Stile per il testo delle card
  static TextStyle getCardTitleStyle(bool isDarkTheme) {
    return TextStyle(
      color: getTitleColor(isDarkTheme), // ← MODIFICATO: Usa getTitleColor invece di getTextColor
      fontSize: 18,
      fontWeight: FontWeight.bold,
    );
  }

  // Stile per il testo secondario delle card
  static TextStyle getCardSubtitleStyle(bool isDarkTheme) {
    return TextStyle(
      color: getSubtitleColor(isDarkTheme),
      fontSize: 14,
    );
  }

  // Decorazione per i container delle card
  static BoxDecoration getCardDecoration(bool isDarkTheme) {
    return BoxDecoration(
      color: getCardColor(isDarkTheme),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black, width: 1), // CONTORNO NERO AGGIUNTO
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDarkTheme ? 0.3 : 0.1),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  // Decorazione per i campi di input
  static InputDecoration getInputDecoration(
    bool isDarkTheme, 
    String hintText, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: getHintColor(isDarkTheme)),
      filled: true,
      fillColor: getFieldColor(isDarkTheme),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffixIcon,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  // Decorazione per la barra di ricerca
  static InputDecoration getSearchDecoration(bool isDarkTheme) {
    return InputDecoration(
      hintText: 'Cerca cartelle, sottocartelle e #tag...',
      hintStyle: TextStyle(color: getHintColor(isDarkTheme)),
      border: InputBorder.none,
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );
  }
}

// Classe per contenere tutti i colori del tema - VERSIONE COMPLETA
class ThemeColors {
  final Color backgroundColor;
  final Color cardColor;
  final Color textColor;
  final Color titleColor; // ← AGGIUNTO: Colore specifico per i titoli
  final Color iconColor; // ← AGGIUNTO: Colore specifico per le icone
  final Color subtitleColor;
  final Color fieldColor;
  final Color hintColor;
  final Color mainBackgroundColor; // NUOVO: Sfondo principale dell'app
  final Color bottomBarColor; // NUOVO: Colore barra di navigazione

  const ThemeColors({
    required this.backgroundColor,
    required this.cardColor,
    required this.textColor,
    required this.titleColor, // ← AGGIUNTO
    required this.iconColor, // ← AGGIUNTO
    required this.subtitleColor,
    required this.fieldColor,
    required this.hintColor,
    required this.mainBackgroundColor,
    required this.bottomBarColor,
  });
  
  // METODO HELPER: Ottiene i colori personalizzati come Map (per retrocompatibilità)
  Map<String, Color> get customColors => {
    'backgroundColor': mainBackgroundColor,
    'bottomBarColor': bottomBarColor,
  };
}