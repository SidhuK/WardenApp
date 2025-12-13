
import CoreData
import Foundation
import os

class DatabasePatcher {
    static func applyPatches(context: NSManagedObjectContext) {
        addDefaultPersonasIfNeeded(context: context)
        patchPersonaOrdering(context: context)
        patchImageUploadsForAPIServices(context: context)
        migratePersonaColorsToSymbols(context: context)
        //resetPersonaOrdering(context: context)
    }

    static func addDefaultPersonasIfNeeded(context: NSManagedObjectContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        if force || !defaults.bool(forKey: AppConstants.defaultPersonasFlag) {
            for (index, persona) in AppConstants.PersonaPresets.allPersonas.enumerated() {
                let newPersona = PersonaEntity(context: context)
                newPersona.name = persona.name
                newPersona.color = persona.symbol
                newPersona.systemMessage = persona.message
                newPersona.addedDate = Date()
                newPersona.temperature = persona.temperature
                newPersona.id = UUID()
                newPersona.order = Int16(index)
            }

	            do {
	                try context.save()
	                defaults.set(true, forKey: AppConstants.defaultPersonasFlag)
	                #if DEBUG
	                WardenLog.coreData.debug("Default assistants added successfully")
	                #endif
	            }
	            catch {
	                WardenLog.coreData.error(
	                    "Failed to add default assistants: \(error.localizedDescription, privacy: .public)"
	                )
	            }
        }
    }

    static func patchPersonaOrdering(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)]

        do {
            let personas = try context.fetch(fetchRequest)
            var needsSave = false

            for (index, persona) in personas.enumerated() {
                if persona.order == 0 && index != 0 {
                    persona.order = Int16(index)
                    needsSave = true
                }
            }

	            if needsSave {
	                try context.save()
	                #if DEBUG
	                WardenLog.coreData.debug("Successfully patched persona ordering")
	                #endif
	            }
	        }
	        catch {
	            WardenLog.coreData.error("Error patching persona ordering: \(error.localizedDescription, privacy: .public)")
	        }
	    }

    static func resetPersonaOrdering(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")

	        do {
            let personas = try context.fetch(fetchRequest)
            for persona in personas {
                persona.order = 0
            }
	            try context.save()
	            #if DEBUG
	            WardenLog.coreData.debug("Successfully reset all persona ordering")
	            #endif

            // Re-apply the ordering patch
            patchPersonaOrdering(context: context)
        }
	        catch {
	            WardenLog.coreData.error("Error resetting persona ordering: \(error.localizedDescription, privacy: .public)")
	        }
	    }

    static func patchImageUploadsForAPIServices(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        
        do {
            let apiServices = try context.fetch(fetchRequest)
            var needsSave = false
            
	            for service in apiServices {
	                if let type = service.type, 
	                   let config = AppConstants.defaultApiConfigurations[type], 
	                   config.imageUploadsSupported && !service.imageUploadsAllowed {
	                    service.imageUploadsAllowed = true
	                    needsSave = true
	                    #if DEBUG
		                    WardenLog.coreData.debug(
		                        "Enabled image uploads for API service: \(service.name ?? "Unnamed", privacy: .public)"
		                    )
	                    #endif
	                }
	            }
            
	            if needsSave {
	                try context.save()
	                #if DEBUG
	                WardenLog.coreData.debug("Successfully patched image uploads for API services")
	                #endif
	            }
	        }
	        catch {
	            WardenLog.coreData.error(
	                "Error patching image uploads for API services: \(error.localizedDescription, privacy: .public)"
	            )
	        }
	    }
    
    static func migrateExistingConfiguration(context: NSManagedObjectContext) {
        let apiServiceManager = APIServiceManager(viewContext: context)
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "APIServiceMigrationCompleted") {
            return
        }

        let apiUrl = defaults.string(forKey: "apiUrl") ?? AppConstants.apiUrlChatCompletions
        let gptModel = defaults.string(forKey: "gptModel") ?? AppConstants.chatGptDefaultModel
        let useStream = defaults.bool(forKey: "useStream")
        let useChatGptForNames = defaults.bool(forKey: "useChatGptForNames")

        var type = "chatgpt"
        var name = "Chat GPT"
        var chatContext = defaults.double(forKey: "chatContext")

        if apiUrl.contains(":11434/api/chat") {
            type = "ollama"
            name = "Ollama"
        }

        if chatContext < 5 {
            chatContext = AppConstants.chatGptContextSize
        }

        let apiService = apiServiceManager.createAPIService(
            name: name,
            type: type,
            url: URL(string: apiUrl)!,
            model: gptModel,
            contextSize: chatContext.toInt16() ?? 15,
            useStreamResponse: useStream,
            generateChatNames: useChatGptForNames
        )

	        if let token = defaults.string(forKey: "gptToken") {
	            if token != "", let apiServiceId = apiService.id {
	                try? TokenManager.setToken(token, for: apiServiceId.uuidString)
	                defaults.set("", forKey: "gptToken")
	                #if DEBUG
	                WardenLog.app.debug("Migrated legacy token to Keychain")
	                #endif
	            }
	        }

        // Set Default Assistant as the default for default API service
        let personaFetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        personaFetchRequest.predicate = NSPredicate(format: "name == %@", "Default Assistant")

	        do {
	            let defaultPersonas = try context.fetch(personaFetchRequest)
	            if let defaultPersona = defaultPersonas.first {
	                #if DEBUG
		                WardenLog.coreData.debug(
		                    "Found default assistant persona: \(defaultPersona.name ?? "", privacy: .public)"
		                )
	                #endif
	                apiService.defaultPersona = defaultPersona
	                try context.save()
	                #if DEBUG
	                WardenLog.coreData.debug("Successfully set default assistant for API service")
	                #endif
	            }
	            else {
	                #if DEBUG
	                WardenLog.coreData.debug("Default Assistant persona not found")
	                #endif
	            }
	        }
	        catch {
	            WardenLog.coreData.error(
	                "Error setting default assistant: \(error.localizedDescription, privacy: .public)"
	            )
	        }

        // Update Chats
        let fetchRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
        do {
            let existingChats = try context.fetch(fetchRequest)
            #if DEBUG
            WardenLog.coreData.debug("Found \(existingChats.count, privacy: .public) existing chat(s) to update")
            #endif

            for chat in existingChats {
                chat.apiService = apiService
                chat.gptModel = apiService.model ?? AppConstants.chatGptDefaultModel
            }

            try context.save()
            #if DEBUG
            WardenLog.coreData.debug("Successfully updated all existing chats with new API service")
            #endif
        }
        catch {
            WardenLog.coreData.error(
                "Error updating existing chats: \(error.localizedDescription, privacy: .public)"
            )
        }

        defaults.set(apiService.objectID.uriRepresentation().absoluteString, forKey: "defaultApiService")

        // Migration completed
        defaults.set(true, forKey: "APIServiceMigrationCompleted")
    }
    
    static func migratePersonaColorsToSymbols(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "PersonaSymbolMigrationCompleted") {
            return
        }
        
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        
        do {
            let personas = try context.fetch(fetchRequest)
            var needsSave = false
            
            // Color to symbol mapping for existing personas
            let colorToSymbolMap: [String: String] = [
                "#FF4444": "person.circle",
                "#FF8800": "pencil.and.outline",
                "#FFCC00": "lightbulb",
                "#33CC33": "book.circle",
                "#3399FF": "chart.line.uptrend.xyaxis",
                "#6633FF": "brain.head.profile",
                "#CC33FF": "arrow.down.circle",
                "#FF3399": "laptopcomputer",
                "#AA6600": "target",
                "#007AFF": "person.circle", // Default color
                "#FF0000": "person.circle"  // Preview color
            ]
            
            for persona in personas {
                if let color = persona.color, color.hasPrefix("#") {
                    // This is a hex color, convert to symbol
                    let symbol = colorToSymbolMap[color] ?? "person.circle"
                    persona.color = symbol
                    needsSave = true
                    #if DEBUG
	                    WardenLog.coreData.debug(
	                        "Migrated persona '\(persona.name ?? "", privacy: .public)' from color to symbol"
	                    )
                    #endif
                }
            }
            
            if needsSave {
                try context.save()
                #if DEBUG
                WardenLog.coreData.debug("Successfully migrated persona colors to symbols")
                #endif
            }
            
            defaults.set(true, forKey: "PersonaSymbolMigrationCompleted")
        }
        catch {
            WardenLog.coreData.error(
                "Error migrating persona colors to symbols: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
