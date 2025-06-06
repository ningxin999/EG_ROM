function [myPCE, PCA]  = PCEPCA(AnParam, experimentaldesign, FEoutput, jj)
% PCEPCA - Constructs a surrogate model using PCE and PCA for high-dimensional outputs.
%
% Inputs:
%   AnParam           - Analysis structure with parameters.
%   experimentaldesign- Training and test data (predefined).
%   FEoutput          - Finite element output data.
%   jj                - Stage number.
%
% Outputs:
%   myPCE             - PCE surrogate model.
%   PCA               - PCA structure for dimensionality reduction.


%% Initialize PCA structure
PCA = initializePCA(AnParam);


%% Create UQ input model
InputOpts_D = setupInputOptions(AnParam, experimentaldesign);
uq_createInput(InputOpts_D);

%% Split data into training and test sets
[N_train, N_test] = splitData(AnParam);


%% ==================SURROGATE CONSTRUCTION=================
%=========================================================
%Define a cell PCA；each observation is created as a structure. 
for kk = 1:AnParam.N_outputfields                                          

    % Prepare training dataset
    PCE_train_dataset = prepareTrainingData(FEoutput, kk, jj, N_train);
    
    % Perform PCA
    PCA{kk}=evalPCA(PCA{kk}, PCE_train_dataset, 0.999999); 

    % Construct surrogate model
    metaopts = setupMetaOptions(AnParam, N_train, experimentaldesign, PCA{kk}, PCE_train_dataset);
    myPCE{kk} = constructSurrogate(metaopts, AnParam.DR, PCA{kk}, PCE_train_dataset);
    


    %SENSITIVEITY ANALYSSIS
    SobolOpts.Type = 'Sensitivity';
    SobolOpts.Method = 'Sobol';
    SobolOpts.Sobol.Order = 1;
    evalc('mySobolAnalysisPCE = uq_createAnalysis(SobolOpts); ');% not printing sobol analysis 
    PCA{kk}.sobol_indice = mySobolAnalysisPCE;
    
    %surrogate metrics
    surrogate_metrics(AnParam,PCA, kk,jj,PCE_train_dataset,myPCE, ...
                    experimentaldesign,FEoutput,N_test,N_train);

end
    
end













%% Helper Functions
function PCA = initializePCA(AnParam)
% Initialize PCA structure for each output field.
PCA = cell(AnParam.N_outputfields, 1);
for ii = 1:AnParam.N_outputfields
    PCA{ii}.minimumPC = 1;
    PCA{ii}.mv = 'null';
    PCA{ii}.V = 'null';
    PCA{ii}.E = 'null';
    PCA{ii}.cumE = 'null';
    PCA{ii}.number = 'null';
    PCA{ii}.offset = ii;
    PCA{ii}.validation_PCA_PCE = 'null';
    PCA{ii}.dataprocess = 'null';
    PCA{ii}.sobol_indice = 'null';
end
end


function InputOpts_D = setupInputOptions(AnParam, experimentaldesign)
% Set up input options for UQ model.
InputOpts_D = struct();
for aa = 1:AnParam.N_parameters
    InputOpts_D.Marginals(aa).Type = 'Uniform';
    InputOpts_D.Marginals(aa).Parameters = [min(experimentaldesign(:, aa)), ...
                                           max(experimentaldesign(:, aa))];
end
end


function [N_train, N_test] = splitData(AnParam)
% Split data into training and test sets.
N_test = AnParam.TestDataRun;
N_train = floor(AnParam.TrainDataPerc * (AnParam.N_RUN - N_test));
if AnParam.N_RUN < N_test
    error('Test runs exceed total FE runs. Reduce test number.');
end
end


function PCE_train_dataset = prepareTrainingData(FEoutput, kk, jj, N_train)
% Prepare training dataset with noise if needed.
if max(FEoutput{kk}{:, jj}(1:N_train, :)) == min(FEoutput{kk}{:, jj}(1:N_train, :))
    epsilon = 1e-10 * randn(size(FEoutput{kk}{:, jj}(1:N_train, :)));
    PCE_train_dataset = FEoutput{kk}{:, jj}(1:N_train, :) + epsilon;
else
    PCE_train_dataset = FEoutput{kk}{:, jj}(1:N_train, :);
end
end

function metaopts = setupMetaOptions(AnParam, N_train, experimentaldesign, PCA, PCE_train_dataset)
% Set up meta-options for surrogate model construction.
metaopts.Type = 'Metamodel';
switch AnParam.Surrogate
    case "PCE"
        metaopts.MetaType = 'PCE';
        metaopts.Method = 'LARS';
        metaopts.TruncOptions.qNorm = 0.75;
        metaopts.Degree = 3:15;
    case "PCK"
        metaopts.MetaType = 'PCK';
        metaopts.Mode = 'sequential';
        metaopts.PCE.Degree = 1:15;
    case "SSE"
        metaopts.MetaType = 'SSE';
        metaopts.ExpOptions.Degree = 0:4;
        metaopts.ExpOptions.Type = 'Metamodel';
        metaopts.ExpOptions.MetaType = 'PCE';
        metaopts.ExpOptions.Degree = 0:4;
end
metaopts.ExpDesign.X = experimentaldesign(1:N_train, :);
if AnParam.DR == "on"
    metaopts.ExpDesign.Y = PCA.score(:, 1:PCA.number);
else
    metaopts.ExpDesign.Y = PCE_train_dataset;
end
end

function myPCE = constructSurrogate(metaopts, DR, PCA, PCE_train_dataset)
% Construct surrogate model (suppress output).
if DR == "on"
    Y = PCA.score(:, 1:PCA.number);
else
    Y = PCE_train_dataset;
end
metaopts.ExpDesign.Y = Y;
[~, myPCE] = evalc('uq_createModel(metaopts)');
end
