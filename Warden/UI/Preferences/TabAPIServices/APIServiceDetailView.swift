
import SwiftUI
import CoreData

struct APIServiceDetailView: View {
    @StateObject private var viewModel: APIServiceDetailViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var lampColor: Color = .gray
    @State private var showingDeleteConfirmation: Bool = false
    @FocusState private var isFocused: Bool
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    init(viewContext: NSManagedObjectContext, apiService: APIServiceEntity?) {
        let viewModel = APIServiceDetailViewModel(viewContext: viewContext, apiService: apiService)
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private let types = AppConstants.apiTypes
    @State private var previousModel = ""
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?
    @State private var loadingIconIndex = 0
    @State private var openRouterProviderFilter = ""

    private var openRouterProviderOptions: [(id: String, displayName: String)] {
        guard viewModel.type == "openrouter" else { return [] }
        let providerIds = Set(viewModel.availableModels.compactMap { ModelMetadata.modelNamespaceID(from: $0) })
        return providerIds
            .map { (id: $0, displayName: ModelMetadata.providerDisplayName(for: $0)) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var filteredModelOptions: [String] {
        var models = viewModel.availableModels

        if viewModel.type == "openrouter", !openRouterProviderFilter.isEmpty {
            models = models.filter { ModelMetadata.modelNamespaceID(from: $0) == openRouterProviderFilter }
        }

        if viewModel.selectedModel != "custom", !models.contains(viewModel.selectedModel) {
            models.append(viewModel.selectedModel)
        }

        return models.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Service Name:")
                    .frame(width: 100, alignment: .leading)

                TextField("API Name", text: $viewModel.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            GroupBox {
                VStack {
                    VStack {
                        HStack {
                            Text("API Type:")
                                .frame(width: 100, alignment: .leading)

                            Image("logo_\(viewModel.type)")
                                .resizable()
                                .renderingMode(.template)
                                .interpolation(.high)
                                .antialiased(true)
                                .frame(width: 14, height: 14)

                            Picker("", selection: $viewModel.type) {
                                ForEach(types, id: \.self) {
                                    Text(AppConstants.defaultApiConfigurations[$0]?.name ?? $0)
                                }
                            }.onChange(of: viewModel.type) { newValue in
                                openRouterProviderFilter = ""
                                viewModel.onChangeApiType(newValue)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    HStack {
                        Text("API URL:")
                            .frame(width: 100, alignment: .leading)

                        TextField("Paste your URL here", text: $viewModel.url)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            viewModel.url = viewModel.defaultApiConfiguration?.url ?? ""
                        }) {
                            Text("Default")
                        }
                    }

                    if (viewModel.defaultApiConfiguration?.apiKeyRef ?? "") != "" {
                        HStack {
                            Text("API Token:")
                                .frame(width: 100, alignment: .leading)

                            TextField("Paste your token here", text: $viewModel.apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isFocused)
                                .blur(radius: !viewModel.apiKey.isEmpty && !isFocused ? 3 : 0.0, opaque: false)
                                .onChange(of: viewModel.apiKey) { newValue in
                                    viewModel.onChangeApiKey(newValue)
                                }
                        }

                        if let apiKeyRef = viewModel.defaultApiConfiguration?.apiKeyRef,
                           let url = URL(string: apiKeyRef) {
                            HStack {
                                Spacer()
                                Link(
                                    "How to get API Token",
                                    destination: url
                                )
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                        }
                    }

                    HStack {
                        Text("LLM Model:")
                            .frame(width: 94, alignment: .leading)

                        if openRouterProviderOptions.count > 1 {
                            Picker("Provider", selection: $openRouterProviderFilter) {
                                Text("All Providers").tag("")
                                ForEach(openRouterProviderOptions, id: \.id) { option in
                                    Text(option.displayName).tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        Picker("", selection: $viewModel.selectedModel) {
                            ForEach(filteredModelOptions, id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                            Text("Enter custom model").tag("custom")
                        }
                        .onChange(of: viewModel.selectedModel) { newValue in
                            if newValue == "custom" {
                                viewModel.isCustomModel = true
                            }
                            else {
                                viewModel.isCustomModel = false
                                viewModel.model = newValue
                            }
                        }
                        .disabled(viewModel.isLoadingModels)
                        .onChange(of: viewModel.availableModels) { _ in
                            guard viewModel.type == "openrouter" else { return }
                            let validIds = Set(viewModel.availableModels.compactMap { ModelMetadata.modelNamespaceID(from: $0) })
                            if !openRouterProviderFilter.isEmpty, !validIds.contains(openRouterProviderFilter) {
                                openRouterProviderFilter = ""
                            }
                        }

                        if AppConstants.defaultApiConfigurations[viewModel.type]?.modelsFetching ?? false {
                            ButtonWithStatusIndicator(
                                title: "Update",
                                action: { viewModel.onUpdateModelsList() },
                                isLoading: viewModel.isLoadingModels,
                                hasError: viewModel.modelFetchError != nil,
                                errorMessage:
                                    "Can't get models from server (or I don't know how), but don't worry - using default list",
                                successMessage: "Click to refresh models list",
                                isSuccess: !viewModel.isLoadingModels && viewModel.modelFetchError == nil
                                    && viewModel.availableModels.count > 0
                            )
                        }
                    }
                    .padding(.top, 8)

                    if viewModel.isCustomModel {
                        VStack {
                            TextField("Enter custom model name", text: $viewModel.model)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }

                    if let apiModelRef = viewModel.defaultApiConfiguration?.apiModelRef,
                       let url = URL(string: apiModelRef) {
                        HStack {
                            Spacer()
                            Link(
                                "Models reference",
                                destination: url
                            )
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                        .padding(.bottom)
                    }

                    HStack {
                        ButtonTestApiTokenAndModel(
                            lampColor: $lampColor,
                            gptToken: viewModel.apiKey,
                            gptModel: viewModel.model,
                            apiUrl: viewModel.url,
                            apiType: viewModel.type
                        )
                    }
                }
                .padding(8)
            }

            // Model Selection Configuration
            if !viewModel.fetchedModels.isEmpty {
                ModelSelectionView(
                    serviceType: viewModel.type,
                    availableModels: viewModel.fetchedModels,
                    onSelectionChanged: { selectedIds in
                        viewModel.updateSelectedModels(selectedIds)
                    }
                )
            }

            VStack {
                HStack {
                    // TODO: implement unlimited context size (is it really needed though?)
                    //                    Toggle(isOn: $viewModel.contextSizeUnlimited) {
                    //                        Text("Unlimited context size")
                    //                    }
                    //                    .disabled(true)
                    //                    Spacer()
                }
                if !viewModel.contextSizeUnlimited {
                    HStack {
                        Slider(
                            value: $viewModel.contextSize,
                            in: 5...100,
                            step: 5
                        ) {
                            Text("Context size")
                        } minimumValueLabel: {
                            Text("5")
                        } maximumValueLabel: {
                            Text("100")
                        }
                        .disabled(viewModel.contextSizeUnlimited)

                        Text(String(format: ("%.0f messages"), viewModel.contextSize))
                            .frame(width: 90)
                    }
                }
            }.padding(.top, 16)

            VStack {
                Toggle(isOn: $viewModel.generateChatNames) {
                    HStack {
                        Text("Automatically generate chat names (using selected model)")
                        Button(action: {
                        }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(
                            "Chat name will be generated based on chat messages. Selected model will be used to generate chat name"
                        )

                        Spacer()
                    }
                }
                Toggle(isOn: $viewModel.useStreamResponse) {
                    HStack {
                        Text("Use stream responses")
                        Button(action: {
                        }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(
                            "If on, the ChatGPT response will be streamed to the client. This will allow you to see the response in real-time. If off, the response will be sent to the client only after the model has finished processing."
                        )

                        Spacer()
                    }
                }

                if viewModel.supportsImageUploads {
                    Toggle(isOn: $viewModel.imageUploadsAllowed) {
                        HStack {
                            Text("Allow image uploads")
                            Button(action: {
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(
                                "If enabled, you can upload images to be processed by the AI. This feature is only available for certain models that support vision capabilities."
                            )

                            Spacer()
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            HStack {
                Text("Default AI Assistant:")
                    .frame(width: 160, alignment: .leading)

                Picker("", selection: $viewModel.defaultAiPersona) {
                    ForEach(personas) { persona in
                        Text(persona.name ?? "Untitled").tag(persona)
                    }
                }
            }

            if AppConstants.openAiReasoningModels.contains(viewModel.model) {
                Text(
                    "💁‍♂️ OpenAI API doesn't support system message and temperature other than 1 for o1 models. Warden will send system message as a user message internally, while temperature will be always set to 1.0"
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if viewModel.apiService != nil {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                }

                Button(action: {
                    viewModel.saveAPIService()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Save")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(16)
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Assistant"),
                message: Text("Are you sure you want to delete this API Service? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.deleteAPIService()
                    presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel()
            )
        }
    }
}
