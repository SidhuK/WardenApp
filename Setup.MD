# Warden Setup: OpenRouter API Key

This guide explains how to add an **OpenRouter** API key to Warden so you can use OpenRouter-backed models for chats.

## Prerequisites

- A working Warden build (or the installed app).
- An OpenRouter account and an API key (the app provides a “Get API Token” link in Settings).

## Add an OpenRouter API service (recommended)

1. Open **Warden**.
2. Open **Preferences**:
   - Menu bar: `Warden` → `Preferences…`
   - Or press `⌘,`
3. Click the **API Services** tab.
4. Click the **+** button (Add Service) in the top-right of the API Services sidebar.
5. Select the new service in the left sidebar, then configure it on the right:

### Connection

- **Service Name**: Set any name you want (example: `OpenRouter`).
- **API Type**: Choose `OpenRouter`.
- **API URL**:
  - Leave the default value unless you have a specific reason to change it.
  - Default: `https://openrouter.ai/api/v1/chat/completions`

### Authentication (API key)

1. In **API Token**, paste your OpenRouter API key.
   - Warden blurs this field when it’s not focused; click into the field to view/edit it.
2. Use **Get API Token** (link under the token field) if you still need to create/copy a key.

### Model

1. In **LLM Model**, choose a model.
   - Warden ships with a default OpenRouter model (currently `deepseek/deepseek-r1:free`).
2. (Optional) Click the **refresh** icon next to the model picker to fetch the latest model list from the provider.
   - Fetching models may require a valid API key.
3. (Optional) Pick **Custom…** to type a model ID manually (example: `openai/gpt-4o`).

### Test and save

1. Click **Test Connection** to validate the API token + model + URL.
2. Click **Save Changes**.
3. (Optional) Click **Set Default** (top-right of the service header) to make this the default API service for new chats.

## Use OpenRouter in a chat

- Start a new chat and ensure the selected/default API service is the OpenRouter service you created.
- If you changed models, verify the **LLM Model** in the OpenRouter service is set to the model you want.

## Where the API key is stored (security)

- Warden stores API tokens in the **macOS Keychain** (not in source code and not in Core Data).
- Internally, the token is saved under the Keychain service name `notfullin.com.macai` and keyed per API service `id` (UUID).

To remove an OpenRouter key:

- Deleting the API Service in Warden stops it being used, but the Keychain entry may remain.
- To fully remove the key, use **Keychain Access** and delete the relevant `api_token_*` entry (advanced/manual).

## Troubleshooting

- **“Invalid API key / unauthorized”**: re-check the token (no extra whitespace), then **Save Changes** and re-test.
- **Models don’t refresh**: ensure the API token is present and valid, then click refresh again.
- **Requests fail after edits**: confirm the OpenRouter URL is still `https://openrouter.ai/api/v1/chat/completions`, then re-test.
