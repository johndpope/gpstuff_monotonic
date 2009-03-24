function [Ef, Varf, p1] = la_pred(gp, tx, ty, x, param, predcf, tstind)
%LA_PRED	Predictions with Gaussian Process Laplace approximation
%
%	Description
%	Y = LA_PRED(GP, TX, TY, X) takes a gp data structure GP together with a
%	matrix X of input vectors, Matrix TX of training inputs and vector TY of 
%       training targets, and evaluates the predictive distribution at inputs. 
%       Returns a matrix Y of (noiseless) output vectors (mean(Y|X, TX, TY)). Each 
%       row of X corresponds to one input vector and each row of Y corresponds to 
%       one output vector.
%
%	Y = LA_PRED(GP, TX, TY, X, 'PARAM') in case of sparse model takes also 
%       string defining, which parameters have been optimized.
%
%	[Y, VarY] = LA_PRED(GP, TX, TY, X, VARARGIN) returns also the variances of Y 
%       (1xn vector).
%
%	See also
%	GPLA_E, GPLA_G, GP_PRED
%
% Copyright (c) 2007-2008 Jarno Vanhatalo

% This software is distributed under the GNU General Public 
% License (version 2 or later); please refer to the file 
% License.txt, included with the software, for details.

    [tn, tnin] = size(tx);
    
    if nargin < 5
        error('The argument telling the optimized/sampled parameters has to be provided.')
    end

    if nargin < 6
        predcf = [];
    end

    

    switch gp.type
      case 'FULL'
        [e, edata, eprior, f, L, La2, b] = gpla_e(gp_pak(gp,'hyper'), gp, tx, ty, 'hyper', param);

        W = La2;
        deriv = b;
        ntest=size(x,1);

        % Evaluate the expectation
        K_nf = gp_cov(gp,x,tx,predcf);
        Ef = K_nf*deriv;

        % Evaluate the variance
        if nargout > 1
            kstarstar = gp_trvar(gp,x,predcf);
            if W >= 0
                V = L\(sqrt(W)*K_nf');
                Varf = kstarstar - sum(V'.*V',2);
            else
                K = gp_trcov(gp,tx);
                %plot(diag(inv(W)))
                %L = chol(K + inv(W))';
                %V = L\(sqrt(W)*K_nf');
                %Varf = kstarstar - sum(V'.*V',2);
                Varf = kstarstar - sum(K_nf.*((K + inv(W))\K_nf')',2);
            end
            for i1=1:ntest
                switch gp.likelih.type
                  case 'probit'
                    p1(i1,1)=normcdf(Ef(i1,1)/sqrt(1+Varf(i1))); % Probability p(y_new=1)
                  case 'poisson'
                    p1 = NaN;
                end
            end
        end

      case 'FIC'
        % Here tstind = 1 if the prediction is made for the training set 
        if nargin > 6
            if length(tstind) ~= size(tx,1)
                error('tstind (if provided) has to be of same lenght as tx.')
            end
        else
             tstind = [];
        end

        u = gp.X_u;
        K_fu = gp_cov(gp, tx, u, predcf);         % f x u
        K_uu = gp_trcov(gp, u, predcf);          % u x u, noiseles covariance K_uu
        K_uu = (K_uu+K_uu')./2;          % ensure the symmetry of K_uu

        m = size(u,1);

        [e, edata, eprior, f, L, La2, b] = gpla_e(gp_pak(gp, param), gp, tx, ty, param);

        deriv = b;
        ntest=size(x,1);

        K_nu=gp_cov(gp,x,u,predcf);
        Ef = K_nu*(K_uu\(K_fu'*deriv));

        % if the prediction is made for training set, evaluate Lav also for prediction points
        if ~isempty(tstind)
            [Kv_ff, Cv_ff] = gp_trvar(gp, x(tstind,:), predcf);
            Luu = chol(K_uu)';
            B=Luu\(K_fu');
            Qv_ff=sum(B.^2)';
            %Lav = zeros(size(La));
            %Lav(tstind) = Kv_ff-Qv_ff;
            Lav = Kv_ff-Qv_ff;            
            Ef(tstind) = Ef(tstind) + Lav.*deriv;
        end

        
        % Evaluate the variance
        if nargout > 1
            W = -feval(gp.likelih.fh_hessian, gp.likelih, ty, f, 'latent');
            kstarstar = gp_trvar(gp,x,predcf);
            Luu = chol(K_uu)';
            La = W.*La2;
            Lahat = 1 + La;
            B = (repmat(sqrt(W),1,m).*K_fu);

            % Components for (I + W^(1/2)*(Qff + La2)*W^(1/2))^(-1) = Lahat^(-1) - L2*L2'
            B2 = repmat(Lahat,1,m).\B;
            A2 = K_uu + B'*B2; A2=(A2+A2)/2;
            L2 = B2/chol(A2);

            % Set params for K_nf
            BB=Luu\(B');
            BB2=Luu\(K_nu');
            Varf = kstarstar - sum(BB2'.*(BB*(repmat(Lahat,1,size(K_uu,1)).\BB')*BB2)',2)  + sum((K_nu*(K_uu\(B'*L2))).^2, 2);
            
            % if the prediction is made for training set, evaluate Lav also for prediction points
            if ~isempty(tstind)
                Varf(tstind) = Varf(tstind) - 2.*sum( BB2(:,tstind)'.*(repmat((La.\Lav),1,m).*BB'),2) ...
                    + 2.*sum( BB2(:,tstind)'*(BB*L).*(repmat(Lav,1,m).*L), 2)  ...
                    - Lav./La.*Lav + sum((repmat(Lav,1,m).*L).^2,2);                
            end
            for i1=1:ntest
                switch gp.likelih.type
                  case 'probit'
                    p1(i1,1)=normcdf(Ef(i1,1)/sqrt(1+Varf(i1))); % Probability p(y_new=1)
                  case 'poisson'
                    p1 = NaN;
                end
            end
        end

      case {'PIC' 'PIC_BLOCK'}
        u = gp.X_u;
        K_fu = gp_cov(gp, tx, u, predcf);         % f x u
        K_uu = gp_trcov(gp, u, predcf);          % u x u, noiseles covariance K_uu
        K_uu = (K_uu+K_uu')./2;          % ensure the symmetry of K_uu
        K_nu=gp_cov(gp,x,u,predcf);

        ind = gp.tr_index;
        ntest = size(x,1);
        m = size(u,1);

        [e, edata, eprior, f, L, La2, b] = gpla_e(gp_pak(gp, param), gp, tx, ty, param);

        deriv = b;

        iKuuKuf = K_uu\K_fu';
        w_bu=zeros(length(x),length(u));
        w_n=zeros(length(x),1);
        for i=1:length(ind)
            w_bu(tstind{i},:) = repmat((iKuuKuf(:,ind{i})*deriv(ind{i},:))', length(tstind{i}),1);
            K_nf = gp_cov(gp, x(tstind{i},:), tx(ind{i},:), predcf);              % n x u
            w_n(tstind{i},:) = K_nf*deriv(ind{i},:);
        end

        Ef = K_nu*(iKuuKuf*deriv) - sum(K_nu.*w_bu,2) + w_n;

        % Evaluate the variance
        if nargout > 1
            W = -feval(gp.likelih.fh_hessian, gp.likelih, ty, f, 'latent');
            kstarstar = gp_trvar(gp,x,predcf);
            sqrtW = sqrt(W);
            % Components for (I + W^(1/2)*(Qff + La2)*W^(1/2))^(-1) = Lahat^(-1) - L2*L2'
            for i=1:length(ind)
                La{i} = diag(sqrtW(ind{i}))*La2{i}*diag(sqrtW(ind{i}));
                Lahat{i} = eye(size(La{i})) + La{i};
            end
            B = (repmat(sqrt(W),1,m).*K_fu);
            for i=1:length(ind)
                B2(ind{i},:) = Lahat{i}\B(ind{i},:);
            end
            A2 = K_uu + B'*B2; A2=(A2+A2)/2;
            L2 = B2/chol(A2);

            iKuuB = K_uu\B';
            KnfL2 = K_nu*(iKuuB*L2);
            Varf = zeros(length(x),1);
            for i=1:length(ind)
                v_n = gp_cov(gp, x(tstind{i},:), tx(ind{i},:),predcf).*repmat(sqrtW(ind{i},:)',length(tstind{i}),1);              % n x u
                v_bu = K_nu(tstind{i},:)*iKuuB(:,ind{i});
                KnfLa = K_nu*(iKuuB(:,ind{i})/chol(Lahat{i}));
                KnfLa(tstind{i},:) = KnfLa(tstind{i},:) - (v_bu + v_n)/chol(Lahat{i});
                Varf = Varf + sum((KnfLa).^2,2);
                KnfL2(tstind{i},:) = KnfL2(tstind{i},:) - v_bu*L2(ind{i},:) + v_n*L2(ind{i},:);
            end
            Varf = kstarstar - (Varf - sum((KnfL2).^2,2));

            for i1=1:ntest
                switch gp.likelih.type
                  case 'probit'
                    p1(i1,1)=normcdf(Ef(i1,1)/sqrt(1+Varf(i1))); % Probability p(y_new=1)
                  case 'poisson'
                    p1 = NaN;
                end
            end
        end
      case 'CS+FIC'
        % Here tstind = 1 if the prediction is made for the training set 
        if nargin > 6
            if length(tstind) ~= size(tx,1)
                error('tstind (if provided) has to be of same lenght as tx.')
            end
        else
             tstind = [];
        end

        n = size(tx,1);
        n2 = size(x,1);
        u = gp.X_u;
        m = length(u);

        [e, edata, eprior, f, L, La2, b] = gpla_e(gp_pak(gp, param), gp, tx, ty, param);
        
        % Indexes to all non-compact support and compact support covariances.
        cf1 = [];
        cf2 = [];
        % Indexes to non-CS and CS covariances, which are used for predictions
        predcf1 = [];
        predcf2 = [];    
        
        ncf = length(gp.cf);
        % Loop through all covariance functions
        for i = 1:ncf        
            % Non-CS covariances
            if ~isfield(gp.cf{i},'cs') 
                cf1 = [cf1 i];
                % If used for prediction
                if ~isempty(find(predcf==i))
                    predcf1 = [predcf1 i]; 
                end
                % CS-covariances
        else
            cf2 = [cf2 i];           
            % If used for prediction
            if ~isempty(find(predcf==i))
                predcf2 = [predcf2 i]; 
            end
            end
        end
        if isempty(predcf1) && isempty(predcf2)
            predcf1 = cf1;
            predcf2 = cf2;
        end
        
        % Determine the types of the covariance functions used
        % in making the prediction.
        if ~isempty(predcf1) && isempty(predcf2)       % Only non-CS covariances
            ptype = 1;
            predcf2 = cf2;
        elseif isempty(predcf1) && ~isempty(predcf2)   % Only CS covariances
            ptype = 2;
            predcf1 = cf1;
        else                                           % Both non-CS and CS covariances
            ptype = 3;
        end
        
        K_fu = gp_cov(gp,tx,u,predcf1);         % f x u
        K_uu = gp_trcov(gp,u,predcf1);    % u x u, noiseles covariance K_uu
        K_uu = (K_uu+K_uu')./2;     % ensure the symmetry of K_uu
        K_nu=gp_cov(gp,x,u,predcf1);

        Kcs_nf = gp_cov(gp, x, tx, predcf2);

        deriv = b;
        ntest=size(x,1);

        % Calculate the predictive mean according to the type of
        % covariance functions used for making the prediction
        if ptype == 1
            Ef = K_nu*(K_uu\(K_fu'*deriv));
        elseif ptype == 2
            Ef = Kcs_nf*deriv;
        else 
            Ef = K_nu*(K_uu\(K_fu'*deriv)) + Kcs_nf*deriv;        
        end

        % evaluate also Lav if the prediction is made for training set
        if ~isempty(tstind)
            [Kv_ff, Cv_ff] = gp_trvar(gp, x(tstind,:), predcf1);
            Luu = chol(K_uu)';
            B=Luu\(K_fu');
            Qv_ff=sum(B.^2)';
            %Lav = zeros(size(Ef));
            %Lav(tstind) = Kv_ff-Qv_ff;
            Lav = Kv_ff-Qv_ff;
        end

        % Add also Lav if the prediction is made for training set
        % and non-CS covariance function is used for prediction
        if ~isempty(tstind) && (ptype == 1 || ptype == 3)
            Ef(tstind) = Ef(tstind) + Lav.*deriv;
        end

        
        % Evaluate the variance
        if nargout > 1
            W = -feval(gp.likelih.fh_hessian, gp.likelih, ty, f, 'latent');
            sqrtW = sparse(1:tn,1:tn,sqrt(W),tn,tn);
            kstarstar = gp_trvar(gp,x,predcf);
            Luu = chol(K_uu)';
            Lahat = sparse(1:tn,1:tn,1,tn,tn) + sqrtW*La2*sqrtW;
            B = sqrtW*K_fu;

            % Components for (I + W^(1/2)*(Qff + La2)*W^(1/2))^(-1) = Lahat^(-1) - L2*L2'
            B2 = Lahat\B;
            A2 = K_uu + B'*B2; A2=(A2+A2)/2;
            L2 = B2/chol(A2);

            % Set params for K_nf
            BB=Luu\(B)';    % sqrtW*K_fu
            BB2=Luu\(K_nu');
            
            m = amd(Lahat);
            % Calculate the predictive variance according to the type
            % covariance functions used for making the prediction
            if ptype == 1 || ptype == 3                            
                % FIC part of the covariance
                Varf = kstarstar - sum(BB2'.*(BB*(Lahat\BB')*BB2)',2) + sum((K_nu*(K_uu\(B'*L2))).^2, 2);
                % Add Lav to Kcs_nf if the prediction is made for the training set
                if  ~isempty(tstind)
                    % Non-CS covariance
                    if ptype == 1         
                        Kcs_nf = sparse(tstind,1:n,Lav,n2,n);                    
                    % Non-CS and CS covariances
                    else                  
                        Kcs_nf = Kcs_nf + sparse(tstind,1:n,Lav,n2,n);
                    end
                    KcssW = Kcs_nf*sqrtW;                    
                    Varf = Varf - sum((KcssW(:,m)/chol(Lahat(m,m))).^2,2) + sum((KcssW*L2).^2, 2) ...
                           - 2.*sum((KcssW*(Lahat\B)).*(K_uu\K_nu')',2) + 2.*sum((KcssW*L2).*(L2'*B*(K_uu\K_nu'))' ,2);
                % In case of both non-CS and CS prediction covariances add 
                % only Kcs_nf if the prediction is not done for the training set 
                elseif ptype == 3
                    KcssW = Kcs_nf*sqrtW;
                    Varf = Varf - sum((KcssW(:,m)/chol(Lahat(m,m))).^2,2) + sum((KcssW*L2).^2, 2) ...
                           - 2.*sum((KcssW*(Lahat\B)).*(K_uu\K_nu')',2) + 2.*sum((KcssW*L2).*(L2'*B*(K_uu\K_nu'))' ,2);
                end
            % Prediction with only CS covariance
            elseif ptype == 2
                KcssW = Kcs_nf*sqrtW;
                Varf = kstarstar - sum((KcssW(:,m)/chol(Lahat(m,m))).^2,2) + sum((KcssW*L2).^2, 2);
            end        

            
            for i1=1:ntest
                switch gp.likelih.type
                  case 'probit'
                    p1(i1,1)=normcdf(Ef(i1,1)/sqrt(1+Varf(i1))); % Probability p(y_new=1)
                  case 'poisson'
                    p1 = NaN;
                end
            end
        end

    end
end