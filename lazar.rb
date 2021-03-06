get '/lazar/?' do
	OpenTox::Algorithm::Lazar.new.rdf
end

post '/lazar/?' do # create a model

	halt 404, "Dataset #{params[:dataset_uri]} not found" unless  training_activities = OpenTox::Dataset.find(params[:dataset_uri])
	halt 404, "No feature_uri parameter." unless params[:feature_uri]
	halt 404, "No feature_generation_uri parameter." unless params[:feature_generation_uri]

	task = OpenTox::Task.create

	Spork.spork(:logger => LOGGER) do

		task.start

		# create features
		fminer_task_uri = OpenTox::Algorithm::Fminer.create_feature_dataset(params)
		fminer_task = OpenTox::Task.find(fminer_task_uri)
		fminer_task.wait_for_completion
		feature_dataset_uri = fminer_task.resource
		training_features = OpenTox::Dataset.find(feature_dataset_uri)
		halt 404, "Dataset #{feature_dataset_uri} not found." if training_features.nil?
		features = []
		p_vals = {}
		effects = {}
		fingerprints = {}
		training_features.data.each do |compound,feats|
			fingerprints[compound] = [] unless fingerprints[compound]
			feats.each do |f|
				f.each do |feature,value|
					if feature.match(/BBRC_representative/)
						fingerprints[compound] << value['smarts']
						unless features.include? value['smarts']
							features << value['smarts']
							p_vals[value['smarts']] = value['p_value'].to_f
							effects[value['smarts']] = value['effect']
						end
					end
				end
			end
		end
		
		model = {
			:activity_dataset => params[:dataset_uri],
			:feature_dataset => feature_dataset_uri.to_s,
			:endpoint => params[:feature_uri],
			:features => features,
			:p_values => p_vals,
			:effects => effects,
			:fingerprints => fingerprints,
			:activities => training_activities.feature_values(params[:feature_uri])
		}

		model_uri = OpenTox::Model::Lazar.create(model.to_yaml)
		LOGGER.info model_uri + " created"

		task.completed(model_uri)
	end
	task.uri

end
