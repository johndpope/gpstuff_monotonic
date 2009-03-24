function gpcf = gpcf_sexp(do, varargin)
%GPCF_SEXP	Create a squared exponential covariance function for Gaussian Process
%
%	Description
%
%	GPCF = GPCF_SEXP('INIT', NIN) Create and initialize squared exponential
%       covariance function for Gaussian process
%
%	The fields and (default values) in GPCF_SEXP are:
%	  type           = 'gpcf_sexp'
%	  nin            = Number of inputs. (NIN)
%	  nout           = Number of outputs. (always 1)
%	  magnSigma2     = Magnitude (squared) for exponential part. 
%                          (0.1)
%	  lengthScale    = Length scale for each input. This can be either scalar corresponding 
%                          isotropic or vector corresponding ARD. 
%                          (repmat(10, 1, nin))
%         p              = Prior structure for covariance function parameters. 
%                          (e.g. p.lengthScale.)
%         fh_pak         = function handle to pack function
%                          (@gpcf_sexp_pak)
%         fh_unpak       = function handle to unpack function
%                          (@gpcf_sexp_unpak)
%         fh_e           = function handle to energy function
%                          (@gpcf_sexp_e)
%         fh_ghyper      = function handle to gradient of energy with respect to hyperparameters
%                          (@gpcf_sexp_ghyper)
%         fh_ginput      = function handle to gradient of function with respect to inducing inputs
%                          (@gpcf_sexp_ginput)
%         fh_cov         = function handle to covariance function
%                          (@gpcf_sexp_cov)
%         fh_trcov       = function handle to training covariance function
%                          (@gpcf_sexp_trcov)
%         fh_trvar       = function handle to training variance function
%                          (@gpcf_sexp_trvar)
%         fh_recappend   = function handle to append the record function 
%                          (gpcf_sexp_recappend)
%
%	GPCF = GPCF_SEXP('SET', GPCF, 'FIELD1', VALUE1, 'FIELD2', VALUE2, ...)
%       Set the values of fields FIELD1... to the values VALUE1... in GPCF.
%
%	See also
%       gpcf_exp, gpcf_matern32, gpcf_matern52, gpcf_ppcs2, gp_init, gp_e, gp_g, gp_trcov
%       gp_cov, gp_unpak, gp_pak
    
% Copyright (c) 2000-2001 Aki Vehtari
% Copyright (c) 2007-2008 Jarno Vanhatalo

% This software is distributed under the GNU General Public
% License (version 2 or later); please refer to the file
% License.txt, included with the software, for details.

    if nargin < 2
        error('Not enough arguments')
    end

    % Initialize the covariance function
    if strcmp(do, 'init')
        nin = varargin{1};
        gpcf.type = 'gpcf_sexp';
        gpcf.nin = nin;
        gpcf.nout = 1;

        % Initialize parameters
        gpcf.lengthScale= repmat(10, 1, nin);
        gpcf.magnSigma2 = 0.1;

        % Initialize prior structure
        gpcf.p=[];
        gpcf.p.lengthScale=[];
        gpcf.p.magnSigma2=[];

        % Set the function handles to the nested functions
        gpcf.fh_pak = @gpcf_sexp_pak;
        gpcf.fh_unpak = @gpcf_sexp_unpak;
        gpcf.fh_e = @gpcf_sexp_e;
        gpcf.fh_ghyper = @gpcf_sexp_ghyper;
        gpcf.fh_ginput = @gpcf_sexp_ginput;
        gpcf.fh_cov = @gpcf_sexp_cov;
        gpcf.fh_covvec = @gpcf_sexp_covvec;
        gpcf.fh_trcov  = @gpcf_sexp_trcov;
        gpcf.fh_trvar  = @gpcf_sexp_trvar;
        gpcf.fh_recappend = @gpcf_sexp_recappend;

        if length(varargin) > 1
            if mod(nargin,2) ~=0
                error('Wrong number of arguments')
            end
            % Loop through all the parameter values that are changed
            for i=2:2:length(varargin)-1
                switch varargin{i}
                  case 'magnSigma2'
                    gpcf.magnSigma2 = varargin{i+1};
                  case 'lengthScale'
                    gpcf.lengthScale = varargin{i+1};
                  case 'fh_sampling'
                    gpcf.fh_sampling = varargin{i+1};
                  case 'metric'
                    gpcf.metric = varargin{i+1};
                    gpcf = rmfield(gpcf, 'lengthScale');
                  otherwise
                    error('Wrong parameter name!')
                end
            end
        end
    end

    % Set the parameter values of covariance function
    if strcmp(do, 'set')
        if mod(nargin,2) ~=0
            error('Wrong number of arguments')
        end
        gpcf = varargin{1};
        % Loop through all the parameter values that are changed
        for i=2:2:length(varargin)-1
            switch varargin{i}
              case 'magnSigma2'
                gpcf.magnSigma2 = varargin{i+1};
              case 'lengthScale'
                gpcf.lengthScale = varargin{i+1};
              case 'fh_sampling'
                gpcf.fh_sampling = varargin{i+1};
              case 'metric'
                gpcf.metric = varargin{i+1};
                gpcf = rmfield(gpcf, 'lengthScale');
              otherwise
                error('Wrong parameter name!')
            end
        end
    end

    function w = gpcf_sexp_pak(gpcf, w)
    %GPCF_SEXP_PAK	 Combine GP covariance function hyper-parameters into one vector.
    %
    %	Description
    %	W = GPCF_SEXP_PAK(GPCF, W) takes a covariance function data structure GPCF and
    %	combines the hyper-parameters into a single row vector W.
    %
    %	The ordering of the parameters in W is:
    %       w = [gpcf.magnSigma2 (hyperparameters of gpcf.lengthScale) gpcf.lengthScale]
    %	  
    %
    %	See also
    %	GPCF_SEXP_UNPAK
        
        if isfield(gpcf,'metric')
            i1=0;i2=1;
            if ~isempty(w)
                i1 = length(w);
            end
            i1 = i1+1;
            w(i1) = gpcf.magnSigma2;
            
            w = feval(gpcf.metric.pak, gpcf.metric, w);
            
        else
            gpp=gpcf.p;
            
            i1=0;i2=1;
            if ~isempty(w)
                i1 = length(w);
            end
            i1 = i1+1;
            w(i1) = gpcf.magnSigma2;
            i2=i1+length(gpcf.lengthScale);
            i1=i1+1;
            w(i1:i2)=gpcf.lengthScale;
            i1=i2;
            
            % Hyperparameters of lengthScale
            if isfield(gpp.lengthScale, 'p') && ~isempty(gpp.lengthScale.p)
                i1=i1+1;
                w(i1)=gpp.lengthScale.a.s;
                if any(strcmp(fieldnames(gpp.lengthScale.p),'nu'))
                    i1=i1+1;
                    w(i1)=gpp.lengthScale.a.nu;
                end
            end
        end
    end




    function [gpcf, w] = gpcf_sexp_unpak(gpcf, w)
    %GPCF_SEXP_UNPAK  Separate covariance function hyper-parameter vector into components.
    %
    %	Description
    %	[GPCF, W] = GPCF_SEXP_UNPAK(GPCF, W) takes a covariance function data structure GPCF
    %	and  a hyper-parameter vector W, and returns a covariance function data
    %	structure  identical to the input, except that the covariance hyper-parameters 
    %   has been set to the values in W. Deletes the values set to GPCF from W and returns 
    %   the modeified W. 
    %
    %	See also
    %	GPCF_SEXP_PAK
    %
        if isfield(gpcf,'metric')
            i1=1;
            gpcf.magnSigma2=w(i1);
            w = w(i1+1:end);
            [metric, w] = feval(gpcf.metric.unpak, gpcf.metric, w);
            gpcf.metric = metric;
        else
            gpp=gpcf.p;
            i1=0;i2=1;
            i1=i1+1;
            gpcf.magnSigma2=w(i1);
            i2=i1+length(gpcf.lengthScale);
            i1=i1+1;
            gpcf.lengthScale=w(i1:i2);
            i1=i2;
            % Hyperparameters of lengthScale
            if isfield(gpp.lengthScale, 'p') && ~isempty(gpp.lengthScale.p)
                i1=i1+1;
                gpcf.p.lengthScale.a.s=w(i1);
                if any(strcmp(fieldnames(gpp.lengthScale.p),'nu'))
                    i1=i1+1;
                    gpcf.p.lengthScale.a.nu=w(i1);
                end
            end        
            w = w(i1+1:end);
        end
    end

    function eprior =gpcf_sexp_e(gpcf, x, t)
    %GPCF_SEXP_E     Evaluate the energy of prior of SEXP parameters
    %
    %	Description
    %	E = GPCF_SEXP_E(GPCF, X, T) takes a covariance function data structure 
    %   GPCF together with a matrix X of input vectors and a matrix T of target 
    %   vectors and evaluates log p(th) x J, where th is a vector of SEXP parameters 
    %   and J is the Jakobian of transformation exp(w) = th. (Note that the parameters 
    %   are log transformed, when packed.)
    %
    %	See also
    %	GPCF_SEXP_PAK, GPCF_SEXP_UNPAK, GPCF_SEXP_G, GP_E
    %
        eprior = 0;
        gpp=gpcf.p;
        
        [n, m] =size(x);

        if isfield(gpcf,'metric')
            eprior=eprior...
                   +feval(gpp.magnSigma2.fe, ...
                          gpcf.magnSigma2, gpp.magnSigma2.a)...
                   -log(gpcf.magnSigma2);
            eprior = eprior + feval(gpcf.metric.e, gpcf.metric, x, t);
            
        else
            % Evaluate the prior contribution to the error. The parameters that
            % are sampled are from space W = log(w) where w is all the "real" samples.
            % On the other hand errors are evaluated in the W-space so we need take
            % into account also the  Jacobian of transformation W -> w = exp(W).
            % See Gelman et.all., 2004, Bayesian data Analysis, second edition, p24.
                    
            eprior=eprior...
                   +feval(gpp.magnSigma2.fe, ...
                          gpcf.magnSigma2, gpp.magnSigma2.a)...
                   -log(gpcf.magnSigma2);
            if isfield(gpp.lengthScale, 'p') && ~isempty(gpp.lengthScale.p)
                eprior=eprior...
                       +feval(gpp.lengthScale.p.s.fe, ...
                              gpp.lengthScale.a.s, gpp.lengthScale.p.s.a)...
                       -log(gpp.lengthScale.a.s);
                if any(strcmp(fieldnames(gpp.lengthScale.p),'nu'))
                    eprior=eprior...
                           +feval(gpp.p.lengthScale.nu.fe, ...
                                  gpp.lengthScale.a.nu, gpp.lengthScale.p.nu.a)...
                           -log(gpp.lengthScale.a.nu);
                end
            end
            eprior=eprior...
                   +feval(gpp.lengthScale.fe, ...
                          gpcf.lengthScale, gpp.lengthScale.a)...
                   -sum(log(gpcf.lengthScale));
        end
    end

    function [DKff, gprior]  = gpcf_sexp_ghyper(gpcf, x, x2, mask)  % , t, g, gdata, gprior, varargin
    %GPCF_SEXP_GHYPER     Evaluate gradient of covariance function and hyper-prior with 
    %                     respect to the hyperparameters.
    %
    %	Description
    %	[GPRIOR, DKff, DKuu, DKuf] = GPCF_SEXP_GHYPER(GPCF, X, T, G, GDATA, GPRIOR, VARARGIN) 
    %   takes a covariance function data structure GPCF, a matrix X of input vectors, a
    %   matrix T of target vectors and vectors GDATA and GPRIOR. Returns:
    %      GPRIOR  = d log(p(th))/dth, where th is the vector of hyperparameters 
    %      DKff    = gradients of covariance matrix Kff with respect to th (cell array with matrix elements)
    %      DKuu    = gradients of covariance matrix Kuu with respect to th (cell array with matrix elements)
    %      DKuf    = gradients of covariance matrix Kuf with respect to th (cell array with matrix elements)
    %
    %   Here f refers to latent values and u to inducing varianble (e.g. Kuf is the covariance 
    %   between u and f). See Vanhatalo and Vehtari (2007) for details.
    %
    %	See also
    %   GPCF_SEXP_PAK, GPCF_SEXP_UNPAK, GPCF_SEXP_E, GP_G

        gpp=gpcf.p;
        [n, m] =size(x);

        i1=0;i2=1;
        
        % Evaluate: DKff{1} = d Kff / d magnSigma2
        %           DKff{2} = d Kff / d lengthScale
        % NOTE! Here we have already taken into account that the parameters are transformed
        % through log() and thus dK/dlog(p) = p * dK/dp

        % evaluate the gradient for training covariance
        if nargin == 2
            Cdm = gpcf_sexp_trcov(gpcf, x);
            
            ii1=1;
            DKff{ii1} = Cdm;

            if isfield(gpcf,'metric')
                dist = feval(gpcf.metric.distance, gpcf.metric, x);
                [gdist, gprior_dist] = feval(gpcf.metric.ghyper, gpcf.metric, x);
                for i=1:length(gdist)
                    ii1 = ii1+1;
                    DKff{ii1} = -2.*Cdm.*dist.*gdist{i};
                end
            else
                % loop over all the lengthScales
                if length(gpcf.lengthScale) == 1
                    % In the case of isotropic SEXP
                    s = 2./gpcf.lengthScale.^2;
                    dist = 0;
                    for i=1:m
                        D = gminus(x(:,i),x(:,i)');
                        dist = dist + D.^2;
                    end
                    D = Cdm.*s.*dist;
                    
                    ii1 = ii1+1;
                    DKff{ii1} = D;
                else
                    % In the case ARD is used
                    for i=1:m
                        s = 2./gpcf.lengthScale(i).^2;
                        dist = gminus(x(:,i),x(:,i)');
                        D = Cdm.*s.*dist.^2;
                        
                        ii1 = ii1+1;
                        DKff{ii1} = D;
                    end
                end
            end
            % Evaluate the gradient of non-symmetric covariance (e.g. K_fu)
        elseif nargin == 3
            if size(x,2) ~= size(x2,2)
                error('gpcf_sexp -> _ghyper: The number of columns in x and x2 has to be the same. ')
            end
            
            ii1=1;
            K = feval(gpcf.fh_cov, gpcf, x, x2);
            DKff{ii1} = K;
            
            if isfield(gpcf,'metric')                
                dist = feval(gpcf.metric.distance, gpcf.metric, x, x2);
                [gdist, gprior_dist] = feval(gpcf.metric.ghyper, gpcf.metric, x, x2);
                for i=1:length(gdist)
                    ii1 = ii1+1;                    
                    DKff{ii1} = -2.*K.*dist.*gdist{i};                    
                end
            else
                % Evaluate help matrix for calculations of derivatives with respect to the lengthScale
                if length(gpcf.lengthScale) == 1
                    % In the case of an isotropic SEXP
                    s = 1./gpcf.lengthScale.^2;
                    dist = 0; dist2 = 0;
                    for i=1:m
                        dist = dist + (gminus(x(:,i),x2(:,i)')).^2;                        
                    end
                    DK_l = 2.*s.*K.*dist;
                    
                    ii1=ii1+1;
                    DKff{ii1} = DK_l;
                else
                    % In the case ARD is used
                    for i=1:m
                        s = 1./gpcf.lengthScale(i).^2;        % set the length
                        dist = gminus(x(:,i),x2(:,i)');
                        DK_l = 2.*s.*K.*dist.^2;
                        
                        ii1=ii1+1;
                        DKff{ii1} = DK_l;
                    end
                end
            end
            % Evaluate: DKff{1}    = d mask(Kff,I) / d magnSigma2
            %           DKff{2...} = d mask(Kff,I) / d lengthScale
        elseif nargin == 4
            if isfield(gpcf,'metric')
                ii1=1;
                DKff{ii1} = feval(gpcf.fh_trvar, gpcf, x);   % d mask(Kff,I) / d magnSigma2
                
                dist = 0;
                [gdist, gprior_dist] = feval(gpcf.metric.ghyper, gpcf.metric, x, [], 1);
                for i=1:length(gdist)
                    ii1 = ii1+1;
                    DKff{ii1} = 0;
                end
            else
                ii1=1;
                DKff{ii1} = feval(gpcf.fh_trvar, gpcf, x);   % d mask(Kff,I) / d magnSigma2
                for i2=1:length(gpcf.lengthScale)
                    ii1 = ii1+1;
                    DKff{ii1}  = 0;                          % d mask(Kff,I) / d lengthScale
                end
            end
        end
        
        if nargout > 1
            if isfield(gpcf,'metric')
                % Evaluate the gprior with respect to magnSigma2
                i1 = i1+1;
                gprior(i1)=feval(gpp.magnSigma2.fg, ...
                                 gpcf.magnSigma2, ...
                                 gpp.magnSigma2.a, 'x').*gpcf.magnSigma2 - 1;
                % Evaluate the data contribution of gradient with respect to lengthScale
                for i2=1:length(gprior_dist)
                    i1 = i1+1;                    
                    gprior(i1)=gprior_dist(i2);
                end
            else
                % Evaluate the gprior with respect to magnSigma2
                i1 = i1+1;
                gprior(i1)=feval(gpp.magnSigma2.fg, ...
                                 gpcf.magnSigma2, ...
                                 gpp.magnSigma2.a, 'x').*gpcf.magnSigma2 - 1;
                % Evaluate the data contribution of gradient with respect to lengthScale
                if length(gpcf.lengthScale)>1
                    for i2=1:gpcf.nin
                        i1=i1+1;
                        gprior(i1)=feval(gpp.lengthScale.fg, ...
                                         gpcf.lengthScale(i2), ...
                                         gpp.lengthScale.a, 'x').*gpcf.lengthScale(i2) - 1;
                    end
                else
                    i1=i1+1;
                    gprior(i1)=feval(gpp.lengthScale.fg, ...
                                     gpcf.lengthScale, ...
                                     gpp.lengthScale.a, 'x').*gpcf.lengthScale -1;
                end
                % Evaluate the prior contribution of gradient with respect to lengthScale.p.s (and lengthScale.p.nu)
                if isfield(gpp.lengthScale, 'p') && ~isempty(gpp.lengthScale.p)
                    i1=i1+1;
                    gprior(i1)=...
                        feval(gpp.lengthScale.p.s.fg, ...
                              gpp.lengthScale.a.s,...
                              gpp.lengthScale.p.s.a, 'x').*gpp.lengthScale.a.s - 1 ...
                        +feval(gpp.lengthScale.fg, ...
                               gpcf.lengthScale, ...
                               gpp.lengthScale.a, 's').*gpp.lengthScale.a.s;
                    if any(strcmp(fieldnames(gpp.lengthScale.p),'nu'))
                        i1=i1+1;
                        gprior(i1)=...
                            feval(gpp.lengthScale.p.nu.fg, ...
                                  gpp.lengthScale.a.nu,...
                                  gpp.lengthScale.p.nu.a, 'x').*gpp.lengthScale.a.nu -1 ...
                            +feval(gpp.lengthScale.fg, ...
                                   gpcf.lengthScale, ...
                                   gpp.lengthScale.a, 'nu').*gpp.lengthScale.a.nu;
                    end
                end
            end
        end
    end


    function [DKff, gprior]  = gpcf_sexp_ginput(gpcf, x, x2)
    %GPCF_SEXP_GIND     Evaluate gradient of covariance function with 
    %                   respect to x.
    %
    %	Descriptioni
    %	[GPRIOR_IND, DKuu, DKuf] = GPCF_SEXP_GIND(GPCF, X, T, G, GDATA_IND, GPRIOR_IND, VARARGIN) 
    %   takes a covariance function data structure GPCF, a matrix X of input vectors, a
    %   matrix T of target vectors and vectors GDATA_IND and GPRIOR_IND. Returns:
    %      GPRIOR  = d log(p(th))/dth, where th is the vector of hyperparameters 
    %      DKuu    = gradients of covariance matrix Kuu with respect to Xu (cell array with matrix elements)
    %      DKuf    = gradients of covariance matrix Kuf with respect to Xu (cell array with matrix elements)
    %
    %   Here f refers to latent values and u to inducing varianble (e.g. Kuf is the covariance 
    %   between u and f). See Vanhatalo and Vehtari (2007) for details.
    %
    %	See also
    %   GPCF_SEXP_PAK, GPCF_SEXP_UNPAK, GPCF_SEXP_E, GP_G
        
        [n, m] =size(x);
        ii1 = 0;
        if nargin == 2
            K = feval(gpcf.fh_trcov, gpcf, x);
            if isfield(gpcf,'metric')
                dist = feval(gpcf.metric.distance, gpcf.metric, x);
                [gdist, gprior_dist] = feval(gpcf.metric.ginput, gpcf.metric, x);
                for i=1:length(gdist)
                    ii1 = ii1+1;
                    DKff{ii1} = -2.*K.*dist.*gdist{ii1};
                    gprior(ii1) = gprior_dist(ii1);
                end
            else
                if length(gpcf.lengthScale) == 1
                    % In the case of an isotropic SEXP
                    s = repmat(1./gpcf.lengthScale.^2, 1, m);
                else
                    s = 1./gpcf.lengthScale.^2;
                end
                for i=1:m
                    for j = 1:n
                        DK = zeros(size(K));
                        DK(j,:) = -2.*s(i).*gminus(x(j,i),x(:,i)');
                        DK = DK + DK';
                        
                        DK = DK.*K;      % dist2 = dist2 + dist2' - diag(diag(dist2));
                        
                        ii1 = ii1 + 1;
                        DKff{ii1} = DK;
                        gprior(ii1) = 0; 
                    end
                end
            end
            
        elseif nargin == 3
            K = feval(gpcf.fh_cov, gpcf, x, x2);
            
            if isfield(gpcf,'metric')
                dist = feval(gpcf.metric.distance, gpcf.metric, x, x2);
                [gdist, gprior_dist] = feval(gpcf.metric.ginput, gpcf.metric, x, x2);
                for i=1:length(gdist)
                    ii1 = ii1+1;
                    DKff{ii1}   = -2.*K.*dist.*gdist{ii1};
                    gprior(ii1) = gprior_dist(ii1);
                end
            else
            
                if length(gpcf.lengthScale) == 1
                    % In the case of an isotropic SEXP
                    s = repmat(1./gpcf.lengthScale.^2, 1, m);
                else
                    s = 1./gpcf.lengthScale.^2;
                end
                
                ii1 = 0;
                for i=1:m
                    for j = 1:n
                        DK= zeros(size(K));
                        DK(j,:) = -2.*s(i).*gminus(x(j,i),x2(:,i)');
                        
                        DK = DK.*K;
                        
                        ii1 = ii1 + 1;
                        DKff{ii1} = DK;
                        gprior(ii1) = 0; 
                    end
                end
            end
        end
    end


    function C = gpcf_sexp_cov(gpcf, x1, x2)
    % GP_SEXP_COV     Evaluate covariance matrix between two input vectors.
    %
    %         Description
    %         C = GP_SEXP_COV(GP, TX, X) takes in covariance function of a Gaussian
    %         process GP and two matrixes TX and X that contain input vectors to
    %         GP. Returns covariance matrix C. Every element ij of C contains
    %         covariance between inputs i in TX and j in X.
    %
    %
    %         See also
    %         GPCF_SEXP_TRCOV, GPCF_SEXP_TRVAR, GP_COV, GP_TRCOV
        
        if isempty(x2)
            x2=x1;
        end
        [n1,m1]=size(x1);
        [n2,m2]=size(x2);

        if m1~=m2
            error('the number of columns of X1 and X2 has to be same')
        end

        if isfield(gpcf,'metric')
            dist = feval(gpcf.metric.distance, gpcf.metric, x1, x2).^2;
            dist(dist<eps) = 0;
            C = gpcf.magnSigma2.*exp(-dist);            
        else
            C=zeros(n1,n2);
            ma2 = gpcf.magnSigma2;
            
            % Evaluate the covariance
            if ~isempty(gpcf.lengthScale)
                s = 1./gpcf.lengthScale.^2;
                if m1==1 && m2==1
                    dd = gminus(x1,x2');
                    dist=dd.^2*s;
                else
                    % If ARD is not used make s a vector of
                    % equal elements
                    if size(s)==1
                        s = repmat(s,1,m1);
                    end
                    dist=zeros(n1,n2);
                    for j=1:m1
                        dd = gminus(x1(:,j),x2(:,j)');
                        dist = dist + dd.^2.*s(:,j);
                    end
                end
                dist(dist<eps) = 0;
                C = ma2.*exp(-dist);
            end
        end
    end

    function C = gpcf_sexp_trcov(gpcf, x)
    % GP_SEXP_TRCOV     Evaluate training covariance matrix of inputs.
    %
    %         Description
    %         C = GP_SEXP_TRCOV(GP, TX) takes in covariance function of a Gaussian
    %         process GP and matrix TX that contains training input vectors. 
    %         Returns covariance matrix C. Every element ij of C contains covariance 
    %         between inputs i and j in TX
    %
    %
    %         See also
    %         GPCF_SEXP_COV, GPCF_SEXP_TRVAR, GP_COV, GP_TRCOV

        if isfield(gpcf,'metric')
            % If other than scaled euclidean metric
            C = gpcf.magnSigma2.*exp(-feval(gpcf.metric.distance, gpcf.metric, x).^2);
            
            [n, m] =size(x);            
            ma = gpcf.magnSigma2;
            
            C = zeros(n,n);
            for ii1=1:n-1
                d = zeros(n-ii1,1);
                col_ind = ii1+1:n;
                d = feval(gpcf.metric.distance, gpcf.metric, x(col_ind,:), x(ii1,:)).^2;                
                C(col_ind,ii1) = d;
            end
            C(C<eps) = 0;
            C = C+C';
            C = ma.*exp(-C);            
        else
            % If scaled euclidean metric
            % Try to use the C-implementation
            C = trcov(gpcf, x);
            
            if isnan(C)
                % If there wasn't C-implementation do here
                [n, m] =size(x)
                
                s = 1./(gpcf.lengthScale);
                s2 = s.^2;
                if size(s)==1
                    s2 = repmat(s2,1,m);
                end
                ma = gpcf.magnSigma2;
                
                C = zeros(n,n);
                for ii1=1:n-1
                    d = zeros(n-ii1,1);
                    col_ind = ii1+1:n;
                    for ii2=1:m
                        d = d+s2(ii2).*(x(col_ind,ii2)-x(ii1,ii2)).^2;
                    end
                    C(col_ind,ii1) = d;
                end
                C(C<eps) = 0;
                C = C+C';
                C = ma.*exp(-C);
            end
        end
    end

    function C = gpcf_sexp_covvec(gpcf, x1, x2, varargin)
    % GPCF_SEXP_COVVEC     Evaluate covariance vector between two input vectors.
    %
    %         Description
    %         C = GPCF_SEXP_COVVEC(GP, TX, X) takes in Gaussian process GP and two
    %         matrixes TX and X that contain input vectors to GP. Returns
    %         covariance vector C, where every element i of C contains covariance
    %         between input i in TX and i in X.
    %
    %
    %         See also
    %         GPCF_SEXP_COV, GPCF_SEXP_TRVAR, GP_COV, GP_TRCOV

        if isempty(x2)
            x2=x1;
        end
        [n1,m1]=size(x1);
        [n2,m2]=size(x2);

        if m1~=m2
            error('the number of columns of X1 and X2 has to be same')
        end

        ma2 = gpcf.magnSigma2;

        di2 = 0;
        s = 1./gpcf.lengthScale.^2;
        for i = 1:m1
            di2 = di2 + s.*(x1(:,i) - x2(:,i)).^2;
        end
        C = gpcf.magnSigma2.*exp(-di2);
    end


    function C = gpcf_sexp_trvar(gpcf, x)
    % GP_SEXP_TRVAR     Evaluate training variance vector
    %
    %         Description
    %         C = GP_SEXP_TRVAR(GPCF, TX) takes in covariance function of a Gaussian
    %         process GPCF and matrix TX that contains training inputs. Returns variance 
    %         vector C. Every element i of C contains variance of input i in TX
    %
    %
    %         See also
    %         GPCF_SEXP_COV, GPCF_SEXP_COVVEC, GP_COV, GP_TRCOV


        [n, m] =size(x);

        C = ones(n,1)*gpcf.magnSigma2;
        C(C<eps)=0;
    end

    function reccf = gpcf_sexp_recappend(reccf, ri, gpcf)
    % RECAPPEND - Record append
    %          Description
    %          RECCF = GPCF_SEXP_RECAPPEND(RECCF, RI, GPCF) takes old covariance
    %          function record RECCF, record index RI and covariance function structure. 
    %          Appends the parameters of GPCF to the RECCF in the ri'th place.
    %
    %          RECAPPEND returns a structure RECCF containing following record fields:
    %          lengthHyper    
    %          lengthHyperNu  
    %          lengthScale    
    %          magnSigma2     
    %
    %          See also
    %          GP_MC and GP_MC -> RECAPPEND

    % Initialize record
        if nargin == 2
            reccf.type = 'gpcf_sexp';
            reccf.nin = ri;
            reccf.nout = 1;

            % Initialize parameters
            reccf.lengthScale= [];
            reccf.magnSigma2 = [];

            % Set the function handles
            reccf.fh_pak = @gpcf_sexp_pak;
            reccf.fh_unpak = @gpcf_sexp_unpak;
            reccf.fh_e = @gpcf_sexp_e;
            reccf.fh_g = @gpcf_sexp_g;
            reccf.fh_cov = @gpcf_sexp_cov;
            reccf.fh_trcov  = @gpcf_sexp_trcov;
            reccf.fh_trvar  = @gpcf_sexp_trvar;
            reccf.fh_recappend = @gpcf_sexp_recappend;
            return
        end

        gpp = gpcf.p;

        if ~isfield(gpcf,'metric')
            % record lengthScale
            if ~isempty(gpcf.lengthScale)
                if ~isempty(gpp.lengthScale)
                    reccf.lengthHyper(ri,:)=gpp.lengthScale.a.s;
                    if isfield(gpp.lengthScale,'p')
                        if isfield(gpp.lengthScale.p,'nu')
                            reccf.lengthHyperNu(ri,:)=gpp.lengthScale.a.nu;
                        end
                    end
                elseif ri==1
                    reccf.lengthHyper=[];
                end
                reccf.lengthScale(ri,:)=gpcf.lengthScale;
            elseif ri==1
                reccf.lengthScale=[];
            end
        end
        % record magnSigma2
        if ~isempty(gpcf.magnSigma2)
            reccf.magnSigma2(ri,:)=gpcf.magnSigma2;
        elseif ri==1
            reccf.magnSigma2=[];
        end
    end
end