import Foundation

// Mocking the OpenRouterHandler parsing logic
func parseJSONResponse(data: Data) -> (String, String)? {
    if let responseString = String(data: data, encoding: .utf8) {
        print("Response: \(responseString)")
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            if let dict = json as? [String: Any],
               let choices = dict["choices"] as? [[String: Any]],
               let lastIndex = choices.indices.last,
               let message = choices[lastIndex]["message"] as? [String: Any],
               let messageRole = message["role"] as? String
            {
                let messageContent = message["content"] as? String
                var finalContent = messageContent ?? ""
                
                // Handle reasoning content if available
                if let reasoningContent = message["reasoning"] as? String {
                    finalContent = "<think>\n\(reasoningContent)\n</think>\n\n\(finalContent)"
                }
                
                // If we have neither content nor reasoning, it's a failure
                if messageContent == nil && message["reasoning"] == nil {
                     print("Error: Both content and reasoning are missing")
                     return nil
                }
                
                return (finalContent, messageRole)
            } else {
                print("Failed to match structure")
            }
        } catch {
            print("Error parsing JSON: \(error.localizedDescription)")
            return nil
        }
    }
    return nil
}

// Test cases
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

print("--- Standard Response ---")
_ = parseJSONResponse(data: standardResponse.data(using: .utf8)!)

print("\n--- Reasoning Response ---")
_ = parseJSONResponse(data: reasoningResponse.data(using: .utf8)!)

print("\n--- Null Content Response ---")
_ = parseJSONResponse(data: nullContentResponse.data(using: .utf8)!)

print("\n--- Empty Content Response ---")
_ = parseJSONResponse(data: emptyContentResponse.data(using: .utf8)!)
