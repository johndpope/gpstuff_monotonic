%DEMO_MODELASSESMENT1   Demonstration for model assesment with DIC, number 
%                       of effective parameters and ten-fold cross validation
%                       
%
%    Description
%    We will consider the regression problem in demo_regression1. The 
%    analysis is conducted with full Gaussian process and FIC sparse
%    approximation. The performance of these two models are compared 
%    by evaluating the DIC statistics, number of efficient parameters 
%    and ten-fold cross validation. The inference will be conducted using
%    maximum a postrior (MAP) estimate for the hyperparameters, via full 
%    Markov chain Monte Carlo (MCMC) and with an integration approximation 
%    (IA) for the hyperparameters.
%
%   See also  DEMO_REGRESSION1

% Copyright (c) 2009 Jarno Vanhatalo

% This software is distributed under the GNU General Public 
% License (version 2 or later); please refer to the file 
% License.txt, included with the software, for details.


% This file is organised in three parts:
%  1) data analysis with full GP model
%  2) data analysis with compact support (CS) GP model
%  3) data analysis with FIC approximation
%  4) data analysis with PIC approximation

%========================================================
% PART 1 data analysis with full GP model
%========================================================

% Load the data
S = which('demo_regression1');
L = strrep(S,'demo_regression1.m','demos/dat.1');
data=load(L);
x = [data(:,1) data(:,2)];
y = data(:,3);
[n, nin] = size(x);

% ---------------------------
% --- Construct the model ---
gpcf1 = gpcf_sexp('init', 'lengthScale', [1 1], 'magnSigma2', 0.2^2);
gpcf2 = gpcf_noise('init', 'noiseSigmas2', 0.2^2);
gpcf2.p.noiseSigmas2 = sinvchi2_p({0.05^2 0.5});
gpcf1.p.lengthScale = logunif_p   %gamma_p({3 7});
gpcf1.p.magnSigma2 = sinvchi2_p({0.05^2 0.5});

gp = gp_init('init', 'FULL', 'regr', {gpcf1}, {gpcf2}, 'jitterSigma2', 0.0001.^2)

% -----------------------------
% --- Conduct the inference ---
%
% We will make the inference first by finding a maximum a posterior estimate 
% for the hyperparameters via gradient based optimization. After this we will
% perform an extensive Markov chain Monte Carlo sampling for the hyperparameters.
% 

% --- MAP estimate using scaled conjugate gradient algorithm ---
%     (see scg for more details)

w=gp_pak(gp, 'hyper');  % pack the hyperparameters into one vector
fe=str2fun('gp_e');     % create a function handle to negative log posterior
fg=str2fun('gp_g');     % create a function handle to gradient of negative log posterior

% set the options for scg2
opt = scg2_opt;
opt.tolfun = 1e-3;
opt.tolx = 1e-3;
opt.display = 1;

% do the optimization
w=scg2(fe, w, opt, fg, gp, x, y, 'hyper');

% Set the optimized hyperparameter values back to the gp structure
gp=gp_unpak(gp,w, 'hyper');

% Evaluate the effective number of parameters. Note that DIC can not be evaluated 
% since we don't have posterior distribution for the hyperparameters.
models{1} = 'full_MAP';
p_eff_latent = gp_peff(gp, x, y);
[DIC2(1), p_eff2(1)] = gp_dic(gp, x, y);

% --- MCMC approach ---

% The sampling options are set to 'opt' structure, which is given to
% 'gp_mc' sampler
opt=gp_mcopt;
opt.nsamples= 300;
opt.repeat=5;
opt.hmc_opt = hmc2_opt;
opt.hmc_opt.steps=4;
opt.hmc_opt.stepadj=0.05;
opt.hmc_opt.persistence=0;
opt.hmc_opt.decay=0.6;
opt.hmc_opt.nsamples=1;
hmc2('state', sum(100*clock));

% Do the sampling (this takes few minutes)
[rfull,g,rstate1] = gp_mc(opt, gp, x, y);

% After sampling we delete the burn-in and thin the sample chain
rfull = thin(rfull, 10, 2);

% Evaluate the effective number of parameters and DIC. Note that 
% the efective number of parameters as a second output, but here 
% we use explicitly the gp_peff function
models{2} = 'full_MCMC'; 
[DIC(2), p_eff(2)] =  gp_dic(rfull, x, y);
[DIC2(2), p_eff2(2)] =  gp_dic(rfull, x, y, [], 'all');

% --- Integration approximation approach ---
opt = gp_iaopt([], 'grid_based');
opt.stepsize = 0.2;
opt.threshold = 10;

gp_array = gp_ia(opt, gp, x, y);

models{3} = 'full_IA'; 
[DIC(3), p_eff(3)] =  gp_dic(gp_array, x, y);
[DIC2(3), p_eff2(3)] =  gp_dic(gp_array, x, y, [], 'all');

% Then the 10 fold cross-validation for the gp_ia result and the 
% point estimate result




%========================================================
% PART 1 data analysis with FIC GP
%========================================================

% ---------------------------
% --- Construct the model ---

% Here we conduct the same analysis as in part 1, but this time we 
% use FIC approximation

% Initialize the inducing inputs in a regular grid over the input space
[u1,u2]=meshgrid(linspace(-1.8,1.8,10),linspace(-1.8,1.8,10));
X_u = [u1(:) u2(:)];

% Create the FIC GP data structure
gp_fic = gp_init('init', 'FIC', 'regr', {gpcf1}, {gpcf2}, 'jitterSigma2', 0.0001.^2, 'X_u', X_u)

% -----------------------------
% --- Conduct the inference ---

% --- MAP estimate using scaled conjugate gradient algorithm ---

%param = 'hyper+inducing'; % optimize hyperparameters and inducing inputs
param = 'hyper';          % optimize only hyperparameters

% set the options
fe=str2fun('gp_e');     % create a function handle to negative log posterior
fg=str2fun('gp_g');     % create a function handle to gradient of negative log posterior
opt = scg2_opt;
opt.tolfun = 1e-3;
opt.tolx = 1e-3;
opt.display = 1;
opt.maxiter = 200;

w = gp_pak(gp_fic, param);          % pack the hyperparameters into one vector
w=scg2(fe, w, opt, fg, gp_fic, x, y, param);       % do the optimization
gp_fic = gp_unpak(gp_fic,w, param);     % Set the optimized hyperparameter values back to the gp structure

% Evaluate the effective number of parameters. Note that DIC can not be evaluated 
% since we don't have posterior distribution for the hyperparameters.
models{4} = 'FIC_MAP';
p_eff_latent(2) = gp_peff(gp_fic, x, y);
[DIC2(4), p_eff2(4)] = gp_dic(gp_fic, x, y);

% --- MCMC approach ---
opt=gp_mcopt;
opt.nsamples= 300;
opt.repeat=5;
opt.hmc_opt.steps=3;
opt.hmc_opt.stepadj=0.02;
opt.hmc_opt.persistence=0;
opt.hmc_opt.decay=0.6;
opt.hmc_opt.nsamples=1;
hmc2('state', sum(100*clock));

% Do the sampling (this takes approximately 3-5 minutes)
[rfic,g2,rstate2] = gp_mc(opt, gp_fic, x, y);

% After sampling we delete the burn-in and thin the sample chain
rfic = thin(rfic, 10, 2);

% Evaluate the effective number of parameters and DIC. Note that 
% the efective number of parameters as a second output, but here 
% we use explicitly the gp_peff function
models{5} = 'FIC_MCMC'; 
[DIC(5), p_eff(5)] =  gp_dic(rfic, x, y);
[DIC2(5), p_eff2(5)] =  gp_dic(rfic, x, y, [], 'all');

% --- Integration approximation approach ---
opt = gp_iaopt([], 'grid_based');
opt.stepsize = 0.2;
opt.threshold = 10;

gpfic_array = gp_ia(opt, gp_fic, x, y);

models{6} = 'FIC_IA'; 
[DIC(6), p_eff(6)] =  gp_dic(gpfic_array, x, y);
[DIC2(6), p_eff2(6)] =  gp_dic(gpfic_array, x, y, [], 'all');

%========================================================
% PART 4 data analysis with PIC approximation
%========================================================

% ---------------------------
% --- Construct the model ---

[p1,p2]=meshgrid(-1.8:0.1:1.8,-1.8:0.1:1.8);
p=[p1(:) p2(:)];

% set the data points into clusters
b1 = [-1.7 -0.8 0.1 1 1.9];
mask = zeros(size(x,1),size(x,1));
trindex={}; tstindex={}; 
for i1=1:4
    for i2=1:4
        ind = 1:size(x,1);
        ind = ind(: , b1(i1)<=x(ind',1) & x(ind',1) < b1(i1+1));
        ind = ind(: , b1(i2)<=x(ind',2) & x(ind',2) < b1(i2+1));
        trindex{4*(i1-1)+i2} = ind';
        ind2 = 1:size(p,1);
        ind2 = ind2(: , b1(i1)<=p(ind2',1) & p(ind2',1) < b1(i1+1));
        ind2 = ind2(: , b1(i2)<=p(ind2',2) & p(ind2',2) < b1(i2+1));
        tstindex{4*(i1-1)+i2} = ind2';
    end
end

% Create the FIC GP data structure
gp_pic = gp_init('init', 'PIC', 'regr', {gpcf1}, {gpcf2}, 'jitterSigma2', 0.001.^2, 'X_u', X_u)
gp_pic = gp_init('set', gp_pic, 'blocks', {'manual', x, trindex});

% -----------------------------
% --- Conduct the inference ---

% --- MAP estimate using scaled conjugate gradient algorithm ---

% param = 'hyper+inducing'; % optimize hyperparameters and inducing inputs
param = 'hyper';          % optimize only hyperparameters

% set the options
opt = scg2_opt;
opt.tolfun = 1e-3;
opt.tolx = 1e-3;
opt.display = 1;

w = gp_pak(gp_pic, param);          % pack the hyperparameters into one vector
[w, opt, flog]=scg2(fe, w, opt, fg, gp_pic, x, y, param);       % do the optimization
gp_pic = gp_unpak(gp_pic,w, param);     % Set the optimized hyperparameter values back to the gp structure

models{7} = 'PIC_MAP';
p_eff_latent(3) = gp_peff(gp_pic, x, y);
[DIC2(7), p_eff2(7)] = gp_dic(gp_pic, x, y);

% --- MCMC approach ---

opt=gp_mcopt;
opt.nsamples= 300;
opt.repeat=5;
opt.hmc_opt.steps=3;
opt.hmc_opt.stepadj=0.02;
opt.hmc_opt.persistence=0;
opt.hmc_opt.decay=0.6;
opt.hmc_opt.nsamples=1;
hmc2('state', sum(100*clock));

% Do the sampling (this takes approximately 3-5 minutes)
[rpic,g2,rstate2] = gp_mc(opt, gp_pic, x, y);

% After sampling we delete the burn-in and thin the sample chain
rpic = rmfield(rpic, 'tr_index');
rpic = thin(rpic, 10, 2);
rpic.tr_index = trindex;

% Evaluate the effective number of parameters and DIC. Note that 
% the efective number of parameters as a second output, but here 
% we use explicitly the gp_peff function
models{8} = 'PIC_MCMC'; 
[DIC(8), p_eff(8)] =  gp_dic(rpic, x, y);
[DIC2(8), p_eff2(8)] =  gp_dic(rpic, x, y, [], 'all');

% --- Integration approximation approach ---
opt = gp_iaopt([], 'grid_based');
opt.stepsize = 0.2;
opt.threshold = 10;

gppic_array = gp_ia(opt, gp_pic, x, y);

models{6} = 'FIC_IA'; 
[DIC(9), p_eff(9)] =  gp_dic(gppic_array, x, y);
[DIC2(9), p_eff2(9)] =  gp_dic(gppic_array, x, y, [], 'all');








l1 = 0.08
l2 = 0.2
l12 = 0.07
Sigma = [l1 l12 ; l12 l2];
iSigma = inv(Sigma);

[X, Y] = meshgrid([-1:0.01:1], [-1:0.01:1]);
xx = [X(:), Y(:)];
p = mnorm_pdf(xx, [0 0], Sigma);

p2 = mnorm_pdf(xx, [0 0], [1./iSigma(1,1) 0 ; 0 1./iSigma(2,2)]);

clf
contour(X,Y,reshape(p, size(X)))
hold on
plot([-1 1], [-1 1])
contour(X,Y,reshape(p2, size(X)), 'k')