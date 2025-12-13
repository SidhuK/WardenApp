#if DEBUG
import Foundation
import os

enum OpenRouterParsingReproduction {
    static func run() {
        WardenLog.app.debug("[Reproduction] OpenRouter parsing smoke test")

        let standardResponse = """
        {
          "id": "gen-123",
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "Hello there!"
              }
            }
          ]
        }
        """

        let reasoningResponse = """
        {
          "id": "gen-123",
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "The answer is 42.",
                "reasoning": "Calculating..."
              }
            }
          ]
        }
        """

        let nullContentResponse = """
        {
          "id": "gen-123",
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": null,
                "reasoning": "Thinking only..."
              }
            }
          ]
        }
        """

        let emptyContentResponse = """
        {
          "id": "gen-123",
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "",
                "reasoning": "Thinking only..."
              }
            }
          ]
        }
        """

        _ = parseJSONResponse(data: Data(standardResponse.utf8))
        _ = parseJSONResponse(data: Data(reasoningResponse.utf8))
        _ = parseJSONResponse(data: Data(nullContentResponse.utf8))
        _ = parseJSONResponse(data: Data(emptyContentResponse.utf8))
    }

    private static func parseJSONResponse(data: Data) -> (String, String)? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = json as? [String: Any],
                  let choices = dict["choices"] as? [[String: Any]],
                  let lastIndex = choices.indices.last,
                  let message = choices[lastIndex]["message"] as? [String: Any],
                  let messageRole = message["role"] as? String else {
                WardenLog.app.debug("[Reproduction] OpenRouter parsing failed: structure mismatch")
                return nil
            }

            let messageContent = message["content"] as? String
            var finalContent = messageContent ?? ""

            if let reasoningContent = message["reasoning"] as? String {
                finalContent = "<think>\n\(reasoningContent)\n</think>\n\n\(finalContent)"
            }

            if messageContent == nil && message["reasoning"] == nil {
                WardenLog.app.debug("[Reproduction] OpenRouter parsing failed: missing content and reasoning")
                return nil
            }

            return (finalContent, messageRole)
        } catch {
            WardenLog.app.debug("[Reproduction] OpenRouter JSON parse error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
