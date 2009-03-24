function [rec, gp, opt] = gp_mc(opt, gp, x, y, xtest, ytest, rec, varargin)
% GP_MC   Monte Carlo sampling for Gaussian process models
%
%   Description
%   [REC, GP, OPT] = GP_MC(OPT, GP, TX, TY) Takes the options structure OPT, 
%   Gaussian process structure GP, training inputs TX and training outputs TY.
%   Returns:
%     REC     - Record structure
%     GP      - The Gaussian process at current state of the sampler
%     OPT     - Options structure containing iformation of the current state 
%               of the sampler (e.g. the random number seed)
%
%   The GP_MC function makes opt.nsamples iterations and stores every opt.repeat'th
%   sample. At each iteration it searches from the options structure strings 
%   specifying the samplers for different parameters. For example, 'hmc_opt' string 
%   in the OPT structure tells that GP_MC should run the hybrid Monte Carlo 
%   sampler. Possiple samplers are:
%      hmc_opt         = hybrid Monte Carlo sampler for covariance/noise function 
%                        parameters (see hmc2)
%      sls_opt         = slice sampler for covariance/noise function parameters 
%                        (see sls2)
%      latent_opt      = sample latent values according to sampler in gp.likelih 
%                        structure (see, for example, likelih_logit)
%      gibbs_opt       = Gibbs sampler for covariance/noise function parameters 
%                        not packed with gp_pak (see gpcf_noiset)
%      likelih_sls_opt = Slice sampling for the parameters of the likelihood function
%                        (see, for example, likelih_negbin)
%
%   The default OPT values for GP_MC are set by GP_MCOPT. The default sampler 
%   options for the actual sampling algorithms are set by their specific fucntions. 
%   See, for example, hmc2_opt.
%
%
%   REC = GP_MC(OPT, GP, TX, TY, X, Y, [], VARARGIN)
%
%   REC = GP_MC(OPT, GP, TX, TY, X, Y, REC, VARARGIN)
%
%   REC = GP_MC(OPT, GP, TX, TY, X, Y, REC, VARARGIN)
%
%
%

% Copyright (c) 1998-2000 Aki Vehtari
% Copyright (c) 2007-2009 Jarno Vanhatalo

% This software is distributed under the GNU General Public 
% License (version 2 or later); please refer to the file 
% License.txt, included with the software, for details.

%#function gp_e gp_g
    
% Check arguments
    if nargin < 4
        error('Not enough arguments')
    end

    % NOTE ! Here change the initialization of energy and gradient function
    % Initialize the error and gradient functions and get 
    % the function handle to them    
    if isfield(opt, 'fh_e')
        me = opt.fh_e;
        mg = opt.fh_g;
    else
        me = @gp_e;
        mg = @gp_g;
    end

    % Set test data
    if nargin < 6 | isempty(xtest)
        xtest=[];ytest =[];
        if isfield(gp, 'ep_opt')
            xtest = x;       % Set the xtest for EP predictions.
        end
    end

    % Initialize record
    if nargin < 7 | isempty(rec)
        % No old record
        rec=recappend;
    else
        ri=size(rec.etr,1);
    end

    % Set the states of samplers if not given in opt structure
    if isfield(opt, 'latent_opt')
        if isfield(opt.latent_opt, 'rstate')
            if ~isempty(opt.latent_opt.rstate)
                latent_rstate = opt.latent_opt.rstate;
            else
                hmc2('state', sum(100*clock))
                latent_rstate=hmc2('state');
            end
        else
            hmc2('state', sum(100*clock))
            latent_rstate=hmc2('state');
        end
    end
    if isfield(opt, 'hmc_opt')
        if isfield(opt.hmc_opt, 'rstate')
            if ~isempty(opt.hmc_opt.rstate)
                hmc_rstate = opt.hmc_opt.rstate;
            else
                hmc2('state', sum(100*clock))
                hmc_rstate=hmc2('state');
            end
        else
            hmc2('state', sum(100*clock))
            hmc_rstate=hmc2('state');
        end
    end    
    if isfield(opt, 'inducing_opt')
        if isfield(opt.inducing_opt, 'rstate')
            if ~isempty(opt.inducing_opt.rstate)
                inducing_rstate = opt.inducing_opt.rstate;
            else
                hmc2('state', sum(100*clock))
                inducing_rstate=hmc2('state');
            end
        else
            hmc2('state', sum(100*clock))
            inducing_rstate=hmc2('state');
        end
    end

    % Set latent values
    if isfield(opt, 'latent_opt')
        z=gp.latentValues';
    else
        z=y;
    end
    
    % Print labels for sampling information
    if opt.display
        fprintf(' cycle  etr      ');
        if ~isempty(ytest)
            fprintf('etst     ');
        end
        if isfield(opt,'hmc_opt')
            fprintf('hrej     ')              % rejection rate of latent value sampling
        end
        if isfield(opt, 'sls_opt')
            fprintf('slsrej  ');
        end
% $$$         if isfield(opt, 'nb_sls_opt')         % Rejection rate of dispersion parameter sampling
% $$$             fprintf('rrej  ');
% $$$         end
        if isfield(opt,'inducing_opt')
            fprintf('indrej     ')              % rejection rate of latent value sampling
        end
        if isfield(opt,'latent_opt')
            fprintf('lrej ')              % rejection rate of latent value sampling
            if isfield(opt.latent_opt, 'sample_latent_scale') 
                fprintf('    lvScale    ')
            end
        end
        fprintf('\n');
    end


    % -------------- Start sampling ----------------------------
    for k=1:opt.nsamples
        
        if opt.persistence_reset
            if isfield(opt, 'hmc_opt')
                hmc_rstate.mom = [];
            end
            if isfield(opt, 'inducing_opt')
                inducing_rstate.mom = [];
            end
            if isfield(opt, 'latent_opt')
                if isfield(opt.latent_opt, 'rstate')
                    opt.latent_opt.rstate.mom = [];
                end
            end
        end
        
        hmcrej = 0;acc=0;
        lrej=0;
        indrej=0;
        for l=1:opt.repeat
            
            % ----------- Sample latent Values  ---------------------
            if isfield(opt,'latent_opt')
                [z, energ, diagnl] = feval(gp.likelih.fh_mcmc, z, opt.latent_opt, gp, x, y, varargin{:});
                gp.latentValues = z(:)';
                z = z(:);
                lrej=lrej+diagnl.rej/opt.repeat;
                if isfield(diagnl, 'opt')
                    opt.latent_opt = diagnl.opt;
                end
            end
            
            % ----------- Sample hyperparameters with HMC --------------------- 
            if isfield(opt, 'hmc_opt')
                w = gp_pak(gp, 'hyper');
                hmc2('state',hmc_rstate)              % Set the state
                [w, energies, diagnh] = hmc2(me, w, opt.hmc_opt, mg, gp, x, z, 'hyper', varargin{:});
                hmc_rstate=hmc2('state');             % Save the current state
                hmcrej=hmcrej+diagnh.rej/opt.repeat;
                if isfield(diagnh, 'opt')
                    opt.hmc_opt = diagnh.opt;
                end
                opt.hmc_opt.rstate = hmc_rstate;
                w=w(end,:);
                gp = gp_unpak(gp, w, 'hyper');
            end
            
            % ----------- Sample hyperparameters with SLS --------------------- 
            if isfield(opt, 'sls_opt')
                w = gp_pak(gp, 'hyper');
                [w, energies, diagns] = sls(me, w, opt.sls_opt, mg, gp, x, z, 'hyper', varargin{:});
                if isfield(diagns, 'opt')
                    opt.sls_opt = diagns.opt;
                end
                w=w(end,:);
                gp = gp_unpak(gp, w, 'hyper');
            end

            % ----------- Sample hyperparameters with Gibbs sampling --------------------- 
            if isfield(opt, 'gibbs_opt')
                % loop over the covariance functions
                ncf = length(gp.cf);
                for i1 = 1:ncf
                    gpcf = gp.cf{i1};
                    if isfield(gpcf, 'fh_gibbs')
                        gpcf = feval(gpcf.fh_gibbs, gp, gpcf, opt.gibbs_opt, x, y);
                        gp.cf{i1} = gpcf;
                    end
                end
                
                % loop over the noise functions                
                nnf = length(gp.noise);
                for i1 = 1:nnf
                    gpcf = gp.noise{i1};
                    if isfield(gpcf, 'fh_gibbs')
                        gpcf = feval(gpcf.fh_gibbs, gp, gpcf, opt.gibbs_opt, x, y);
                        gp.noise{i1} = gpcf;
                    end                    
                end
            end
            
            % ----------- Sample hyperparameters of the likelihood with SLS --------------------- 
            if isfield(opt, 'likelih_sls_opt')
                w = gp_pak(gp, 'likelih');
                fe = @(w, likelih) (- feval(likelih.fh_e, feval(likelih.fh_unpak, w, likelih), y, z));
                [w, energies, diagns] = sls(fe, w, opt.likelih_sls_opt, [], gp.likelih);
                if isfield(diagns, 'opt')
                    opt.likelih_sls_opt = diagns.opt;
                end
                w=w(end,:);
                gp = gp_unpak(gp, w, 'likelih');
            end
            
            % ----------- Sample inducing inputs with hmc  ------------ 
            if isfield(opt, 'inducing_opt')
                w = gp_pak(gp, 'inducing');
                hmc2('state',inducing_rstate)         % Set the state
                [w, energies, diagnh] = hmc2(me, w, opt.inducing_opt, mg, gp, x, z, 'inducing');
                inducing_rstate=hmc2('state');        % Save the current state
                indrej=indrej+diagnh.rej/opt.repeat;
                if isfield(diagnh, 'opt')
                    opt.inducing_opt = diagnh.opt;
                end
                opt.inducing_opt.rstate = inducing_rstate;
                w=w(end,:);
                gp = gp_unpak(gp, w, 'inducing');
            end
            
            
            % ----------- Sample inputs  ---------------------
            
            
        end % ------------- for l=1:opt.repeat -------------------------  
        
        % ----------- Set record -----------------------    
        ri=ri+1;
        rec=recappend(rec);
        
        % Display some statistics  THIS COULD BE DONE NICER ALSO...
        if opt.display
            fprintf(' %4d  %.3f  ',ri, rec.etr(ri,1));
            if ~isempty(ytest)
                fprintf('%.3f  ',rec.etst(ri,1));
            end
            if isfield(opt, 'hmc_opt')
                fprintf(' %.1e  ',rec.hmcrejects(ri));
            end
            if isfield(opt, 'sls_opt')
                fprintf('sls  ');
            end
            if isfield(opt, 'inducing_opt')
                fprintf(' %.1e  ',rec.indrejects(ri)); 
            end
            if isfield(opt,'latent_opt')
                fprintf('%.1e',rec.lrejects(ri));
                fprintf('  ');
                if isfield(diagnl, 'lvs')
                    fprintf('%.6f', diagnl.lvs);
                end
            end
            if isfield(opt,'noise_opt')
                fprintf('%.2f', rec.noise{1}.nu(ri));
            end      
            fprintf('\n');
        end
    end
      
    %------------------------------------------------------------------------
    function rec = recappend(rec)
    % RECAPPEND - Record append
    %          Description
    %          REC = RECAPPEND(REC, RI, GP, P, T, PP, TT, REJS, U) takes
    %          old record REC, record index RI, training data P, target
    %          data T, test data PP, test target TT and rejections
    %          REJS. RECAPPEND returns a structure REC containing following
    %          record fields of:
        
        ncf = length(gp.cf);
        nn = length(gp.noise);
        
        if nargin == 0   % Initialize record structure
            rec.nin = gp.nin;
            rec.nout = gp.nout;
            rec.type = gp.type;
            % If sparse model is used save the information about which
            switch gp.type
              case 'FIC'
                rec.X_u = [];
                if isfield(opt, 'inducing_opt')
                    rec.indrejects = 0;
                end
              case {'PIC' 'PIC_BLOCK'}
                rec.X_u = [];
                if isfield(opt, 'inducing_opt')
                    rec.indrejects = 0;
                end
                rec.tr_index = gp.tr_index;
              case 'CS+FIC'
                rec.X_u = [];
                if isfield(opt, 'inducing_opt')
                    rec.indrejects = 0;
                end

              otherwise
                % Do nothing
            end
            if isfield(gp,'latentValues')
                rec.latentValues = [];
                rec.lrejects = 0;
            end
            rec.jitterSigmas = [];
            rec.hmcrejects = 0;
            
            if isfield(gp, 'site_tau')
                rec.site_tau = [];
                rec.site_nu = [];
                rec.Ef = [];
                rec.Varf = [];
                rec.p1 = [];
            end
            
            % Initialize the records of covariance functions
            for i=1:ncf
                cf = gp.cf{i};
                rec.cf{i} = feval(cf.fh_recappend, [], gp.nin);
                % Initialize metric structure
                if isfield(cf,'metric')
                    rec.cf{i}.metric = feval(cf.metric.recappend, cf.metric, gp.nin);
                end
            end
            for i=1:nn
                noise = gp.noise{i};
                rec.noise{i} = feval(noise.fh_recappend, [], gp.nin);
            end
            
            % Initialize the record for likelihood
            if isstruct(gp.likelih)
                likelih = gp.likelih;
                rec.likelih = feval(likelih.fh_recappend, [], []);
            end
            
            rec.e = [];
            rec.edata = [];
            rec.eprior = [];
            rec.etr = [];
            ri = 1;
            lrej = 0;
            indrej = 0;
            hmcrej=0;
        end

        % Set the record for every covariance function
        for i=1:ncf
            gpcf = gp.cf{i};
            rec.cf{i} = feval(gpcf.fh_recappend, rec.cf{i}, ri, gpcf);
            % Record metric structure
            if isfield(gpcf,'metric')
                rec.cf{i}.metric = feval(rec.cf{i}.metric.recappend, rec.cf{i}.metric, ri, gpcf.metric);
            end
        end

        % Set the record for every noise function
        for i=1:nn
            noise = gp.noise{i};
            rec.noise{i} = feval(noise.fh_recappend, rec.noise{i}, ri, noise);
        end

        % Set the record for likelihood
        if isstruct(gp.likelih)
            likelih = gp.likelih;
            rec.likelih = feval(likelih.fh_recappend, rec.likelih, ri, likelih);
        end

        % Set jitterSigmas to record
        if ~isempty(gp.jitterSigmas)
            rec.jitterSigmas(ri,:) = gp.jitterSigmas;
        end

        % Set the latent values to record structure
        if isfield(gp, 'latentValues')
            rec.latentValues(ri,:)=gp.latentValues;
        end

        % Set the site parameters to record structure
        if isfield(gp, 'site_tau')
            [E1, E2, E3, tau, nu] = feval(me, gp_pak(gp,'hyper'), gp, x, y, 'hyper', varargin{:});
            switch gp.type
              case {'PIC' 'PIC_BLOCK'}
                [Ef, Varf] = ep_pred(gp, x, y, xtest, 'hyper', [], gp.tr_index);
              otherwise
                [Ef, Varf] = ep_pred(gp, x, y, xtest, 'hyper');
            end
            rec.site_tau(ri,:)=tau;
            rec.site_nu(ri,:)=nu;
            rec.Ef(ri,:) = Ef';
            rec.Varf(ri,:) = Varf';
            rec.Zep(ri,:) = E1;
        end

        % Set the inducing inputs in the record structure
        switch gp.type
          case {'FIC', 'PIC', 'PIC_BLOCK', 'CS+FIC'}
            rec.X_u(ri,:) = gp.X_u(:)';
        end
        if isfield(opt, 'inducing_opt')
            rec.indrejects(ri,1)=indrej; 
        end

        % Record training error and rejects
        if isfield(gp,'latentValues')
            
            [rec.e(ri,:),rec.edata(ri,:),rec.eprior(ri,:)] = feval(me, gp_pak(gp, 'hyper'), gp, x, gp.latentValues', 'hyper', varargin{:});
            rec.etr(ri,:) = rec.e(ri,:);   % feval(gp.likelih_e, gp.latentValues', gp, p, t, varargin{:});
                                           % Set rejects 
            rec.lrejects(ri,1)=lrej;
        else
            %            fprintf('error')
            [rec.e(ri,:),rec.edata(ri,:),rec.eprior(ri,:)] = feval(me, gp_pak(gp, 'hyper'), gp, x, y, 'hyper', varargin{:});
            rec.etr(ri,:) = rec.e(ri,:);
        end
        
        if isfield(opt, 'hmc_opt')
            rec.hmcrejects(ri,1)=hmcrej; 
        end

        % If inputs are sampled set the record which are on at this moment
        if isfield(gp,'inputii')
            rec.inputii(ri,:)=gp.inputii;
        end
    end
end