#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Explicit simulator preview only. No key/configuration changes, network calls, or stored transcript.
@MainActor
enum DemoCoachHarness {
    static func configureIfRequested(_ coach: AICoachEngine) {
        guard CommandLine.arguments.contains("--demo-coach") else { return }
        coach.demoMode = true
        coach.messages = [
            ChatMessage(role: .user, text: "Comment lire ma semaine de sommeil ?"),
            ChatMessage(role: .assistant, text: """
            **Aperçu local · données fictives**

            Dans cet exemple, la durée de sommeil passe de **6 h 40 à 7 h 35** au cours de la semaine. Cette conversation est préécrite pour tester l’interface : elle n’analyse pas tes données.

            ### Une lecture simple
            - Regarde d’abord la durée et les horaires de chaque nuit.
            - Compare ensuite plusieurs nuits, plutôt qu’un score isolé.
            - Ouvre la chronologie pour retrouver les détails disponibles.

            L’historique reste accessible pendant une nouvelle réponse. Fais défiler vers le haut : le Coach te laisse lire, puis « Dernière réponse » te ramène en bas lorsque tu le décides.
            """),
            ChatMessage(role: .user, text: "Et comment préparer ma journée sans tout compliquer ?"),
            ChatMessage(role: .assistant, text: """
            **Exemple de conversation, sans appel à une IA**

            ### Trois repères
            **1. Ta dernière nuit.** Retrouve sa durée, ses horaires et sa chronologie depuis Sommeil.

            **2. La tendance.** Dans cet exemple synthétique, plusieurs nuits deviennent plus longues. Cela illustre la lecture d’une série ; ce n’est pas une recommandation personnelle.

            **3. Une action facile à retrouver.** Tu peux ouvrir une séance, consulter un détail ou préparer une question, sans perdre la nuit que tu regardais.

            ### Essaie le Coach
            Envoie une question pour voir une réponse locale apparaître progressivement. Tu peux l’arrêter, puis réessayer sans dupliquer la question. Pour tester un échec récupérable, écris « test erreur » : la première tentative échoue et la suivante aboutit.

            Toutes les valeurs et tous les textes de cet aperçu sont fictifs. Aucune clé API n’est utilisée et aucune requête n’est envoyée.
            """)
        ]
        var attempts: [String: Int] = [:]
        coach.streamOverride = { wire, delta in
            let question = wire.last(where: { $0.role == .user })?.content ?? ""
            attempts[question, default: 0] += 1
            let attempt = attempts[question, default: 0]
            try await Task.sleep(nanoseconds: 450_000_000)
            if question.localizedCaseInsensitiveContains("test erreur"), attempt == 1 {
                throw AICoachError.network("Échec de démonstration : touche Réessayer")
            }
            let reply = """
            **Réponse de démonstration locale**

            Cette réponse est préécrite : aucune donnée personnelle n’a été lue ou envoyée à un fournisseur.

            Dans l’exemple, sept nuits illustrent comment retrouver une durée, consulter les horaires et comparer la régularité. Le but de cet aperçu est de vérifier que ces informations restent faciles à lire.

            **Garde le contrôle de la lecture.** Tu peux remonter dans l’historique pendant que ce texte apparaît. Le défilement ne doit pas te ramener en bas contre ton gré. « Dernière réponse » reprend le suivi lorsque tu le souhaites.

            **Une conversation qui reste fluide.** Le champ s’agrandit avec ton message, le bouton Arrêter interrompt cette simulation et Réessayer reprend la même question. L’historique de cet aperçu reste en mémoire uniquement.
            """
            for word in reply.components(separatedBy: " ") {
                try Task.checkCancellation()
                delta(word + " ")
                try await Task.sleep(nanoseconds: 65_000_000)
            }
        }
    }
}
#endif
